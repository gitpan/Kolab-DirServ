use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Kolab::DirServ',
    'VERSION_FROM'	=> 'DirServ.pm', # finds $VERSION
    'PREREQ_PM'		=> {
     'Kolab::DirServ::Config' => '>=0.3',
     'Kolab::Config'          => '>0.1',
     'Kolab::Util'            => '>0.1',
     'MIME::Entity'           => '0',
     #'MIME::Parser'           => '0',
     #'MIME::Body'             => '0',
     #'Net::LDAP'              => '0',
     #'Net::LDAP::LDIF'        => '0',
     #'Net::LDAP::Entry'       => '0',
     'Mail::IMAPClient'       => '0',
     'URI'                    => '0',
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'DirServ.pm', # retrieve abstract from module
       AUTHOR     => 'root <root@(none)>') : ()),
);
