#!perl
use strict;
use warnings;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
  ABSTRACT => "Extensible Perl internet server",
  AUTHOR => 'Paul Seamons <paul@seamons.com> and Rob Brown <bbb@cpan.org>',
  DISTNAME => "Net-Server",
  EXE_FILES => [ "bin/net-server" ],
  LICENSE => "perl",
  NAME => "Net::Server",
  PREREQ_PM => {
    "Carp" => 0,
    "File::Temp" => 0,
    "IO::Socket" => 0,
    "POSIX" => 0,
    "Socket" => 0,
    "Time::HiRes" => 0
  },
  VERSION_FROM => "lib/Net/Server.pm",
  test => {
    "TESTS" => "t/*.t"
  },
  META_MERGE => {
    'meta-spec' => { version => 2 },
     resources => {
         homepage => "https://github.com/rhandom/perl-net-server",
         repository => {
             type => 'git',
             url  => 'https://github.com/rhandom/perl-net-server',
             web  => 'https://github.com/rhandom/perl-net-server',
         },
         bugtracker => {
             #web => 'https://rt.cpan.org/Dist/Display.html?Name=Net-Server'
             web => 'https://github.com/rhandom/perl-net-server/issues'
         },
     },
  },
);

delete $WriteMakefileArgs{LICENSE}    if !eval { ExtUtils::MakeMaker->VERSION(6.31) };
delete $WriteMakefileArgs{META_MERGE} if !eval { ExtUtils::MakeMaker->VERSION(6.46) };

WriteMakefile(%WriteMakefileArgs);
