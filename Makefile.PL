use ExtUtils::MakeMaker;


my %args = (
            'NAME'	      => 'Net::Server',
            'VERSION_FROM'    => 'lib/Net/Server.pm',
            
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

README: lib/Net/Server.pm
\tpod2text lib/Net/Server.pm >README
  ^;
}

1;
