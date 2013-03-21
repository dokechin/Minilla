package Minilla::CLI::Dist;
use strict;
use warnings;
use utf8;
use Minilla::WorkDir;

sub run {
    my ($self, @args) = @_;

    my $test = 1;
    $self->parse_options(
        \@args,
        'test!' => \$test,
    );

    Minilla::WorkDir->make_tar_ball($self, $test);
}

1;
__END__

=head1 NAME

Minilla::CLI::Dist - Make tar ball distribution

=head1 SYNOPSIS

    % minil dist

=head1 DESCRIPTION

This subcommand makes distribution tar ball.

