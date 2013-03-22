package Minilla::Migrate;
use strict;
use warnings;
use utf8;

use File::pushd;
use CPAN::Meta;
use Path::Tiny;
use File::Find::Rule;

use Minilla::Util qw(slurp spew);

use Moo;

has c => (
    is => 'ro',
    required => 1,
);

has use_mb_tiny => (
    is => 'lazy',
);

has project => (
    is => 'lazy',
);

no Moo;

sub _build_project {
    my $self = shift;

    Minilla::Project->new(
        c => $self->c,
    );
}

sub _build_use_mb_tiny {
    my $self = shift;
    (0+(File::Find::Rule->file()->name(qr/\.(c|xs)$/)->in('.')) == 0);
}

sub run {
    my $self = shift;

    my $guard = pushd($self->project->dir);

    # Generate cpanfile from Build.PL
    unless (-f 'cpanfile') {
        $self->migrate_cpanfile();
    }

    $self->generate_license();
    $self->generate_build_pl();

    # M::B::Tiny protocol
    if (-d 'bin' && !-e 'script') {
        $self->c->cmd('git mv bin script');
    }
    # TODO move top level *.pm to lib/?

    $self->remove_unused_files();
    $self->migrate_gitignore();
    $self->migrate_meta_json();

    $self->c->cmd('git add META.json');
}

sub generate_license {
    my ($self) = @_;

    unless (-f 'LICENSE') {
        path('LICENSE')->spew($self->project->metadata->license->fulltext());
    }
}

sub migrate_cpanfile {
    my ($self) = @_;

    if (-f 'Build.PL') {
        if (slurp('Build.PL') =~ /Module::Build::Tiny/) {
            $self->c->infof("M::B::Tiny was detected. I hope META.json is already exists here\n");
        } else {
            $self->c->cmd($^X, 'Build.PL');
            $self->c->cmd($^X, 'Build', 'build');
            $self->c->cmd($^X, 'Build', 'distmeta');
        }
    } elsif (-f 'Makefile.PL') {
        $self->c->cmd($^X, 'Makefile.PL');
        $self->c->cmd('make metafile');
    } else {
        $self->c->error("There is no Build.PL/Makefile.PL");
    }

    unless (-f 'META.json') {
        $self->c->error("Cannot generate META.json\n");
    }

    my $meta = CPAN::Meta->load_file('META.json');
    my $prereqs = $meta->effective_prereqs->as_string_hash;

    if ($self->use_mb_tiny) {
        delete $prereqs->{configure}->{runtime}->{'Module::Build'};
        $prereqs->{configure}->{runtime}->{'Module::Build::Tiny'} = 0;
    } else {
        $prereqs->{configure}->{runtime}->{'Module::Build'}    = 0.40;
        $prereqs->{configure}->{runtime}->{'Module::CPANfile'} = 0;
    }

    my $ret = '';
    for my $phase (qw(runtime configure build develop)) {
        my $indent = $phase eq 'runtime' ? '' : '    ';
        $ret .= "on $phase => sub {\n" unless $phase eq 'runtime';
        for my $type (qw(requires recommends)) {
            while (my ($k, $version) = each %{$prereqs->{$phase}->{$type}}) {
                $ret .= "${indent}$type '$k' => '$version';\n";
            }
        }
        $ret .= "};\n\n" unless $phase eq 'runtime';
    }
    spew('cpanfile', $ret);

    $self->c->cmd('git add cpanfile');
}

sub generate_build_pl {
    my ($self) = @_;

    if ($self->use_mb_tiny) {
        path('Build.PL')->spew("use Module::Build::Tiny;\nBuild_PL()");
    } else {
        my $dist = path($self->project->dir)->basename;
           $dist =~ s/^p5-//;
        (my $module = $dist) =~ s!-!::!g;
        path('Build.PL')->spew(Minilla::Skeleton->render_build_mb_pl({
            dist   => $dist,
            module => $module,
        }));
    }
}

sub remove_unused_files {
    my $self = shift;

    # remove some unusable files
    for my $file (qw(
        Makefile.PL
        MANIFEST
        MANIFEST.SKIP
        .shipit
        xt/97_podspell.t
        xt/99_pod.t
    )) {
        if (-f $file) {
            $self->c->cmd("git rm $file");
        }
    }

    for my $file (qw(
        MANIFEST.SKIP.bak
        MANIFEST.bak
    )) {
        if (-f $file) {
            path($file)->remove;
        }
    }
}

sub migrate_meta_json {
    my ($self) = @_;

    $self->project->cpan_meta('unstable')->save(
        'META.json' => {
            version => 2.0
        }
    );
}

sub migrate_gitignore {
    my ($self) = @_;

    my @lines;
    
    if (-f '.gitignore') {
        @lines = path('.gitignore')->lines({chomp => 1});
    }

    # remove META.json from ignored file list
        @lines = grep !/^META\.json$/, @lines;

    my $tarpattern = sprintf('%s-*.tar.gz', $self->project->dist_name);
    # Add some lines
    for my $fname (qw(
        .build
        _build_params
        /Build
        !Build/
        !META.json
    ), $tarpattern) {
        unless (grep /\A$fname\z/, @lines) {
            push @lines, $fname;
        }
    }

    path('.gitignore')->spew(join('', map { "$_\n" } @lines));
}



1;
