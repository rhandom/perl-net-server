use ExtUtils::MakeMaker;


my %args = (
            'NAME'	      => 'Net::Server',
            'VERSION_FROM'    => 'lib/Net/Server.pm',
            'ABSTRACT_FROM'   => 'lib/Net/Server.pm',
            'PREREQ_PM'	      => {
              'IO::Socket' => 0,
              Socket       => 0,
              POSIX        => 0,
            },

            dist              => {
              DIST_DEFAULT => 'all tardist',
              COMPRESS     => 'gzip -vf',
              SUFFIX       => '.gz',
            },

            clean             => {
              FILES        => '*~',
            },

            realclean         => {
              FILES        => '*~',
            },

            );

WriteMakefile(%args);

package MY;

sub libscan {
  my $self = shift;
  my $path = shift;
  ($path =~ / \bCVS\b | \~$ /x) ? undef : $path;
}

sub postamble {
  return qq^

pm_to_blib: README

README: \$(VERSION_FROM)
	pod2text \$(VERSION_FROM) > README
^;
}

sub processPL {
  my $self = shift;
  my $block = $self->SUPER::processPL(@_);
  # "Version:" in spec needs to match
  # "$VERSION" from VERSION_FROM
  $block =~ s%(spec.PL\s*)$%$1 \$\(VERSION_FROM\)%m;
  $block;
}

1;
