package Kolab::DirServ;

use 5.008;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Kolab::DirServ ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	&notify_new_alias &notify_remove_alias &notify_modify_alias &handle_notifications
);

# Preloaded methods go here.
our $VERSION = '0.04';
use Kolab::DirServ::Config;
use Kolab::Config;
use Kolab::Util;
use MIME::Entity;
use MIME::Parser;
use MIME::Body;
use Net::LDAP;
use Net::LDAP::LDIF;
use Net::LDAP::Entry;
use Mail::IMAPClient;
use URI;
use IO::File;
use POSIX qw(tmpnam);

my ($name,$fh);
END { if (defined $name) {unlink($name) or die "Couldn't unlink $name " }}

#Send a notification to add alias to peers
sub notify_new_alias {
	my $notify = shift;
	my $entry = $notify->clone;

	#If no peers, ignore the request
	if (length(@addressbook_peers) == 0) { return 0 };
	
	#Clean up some unwanted attributes
	$entry->delete('userpassword');
	$entry->delete('uid');
	#$entry->delete('alias');

	#Set up temporary file
	do { $name = tmpnam() }
		until $fh = IO::File->new($name, O_RDWR|O_CREAT|O_EXCL);
	

	#Write our LDAP entry to temp file in LDIF format
	my $ldif = Net::LDAP::LDIF->new( $fh, "r", onerror => 'undef' );
	$ldif->write_entry($entry);

	foreach my $peer (@addressbook_peers) {
		#Seek to the beginning of the temp file
		seek ($fh,0,0);

		my $top = MIME::Entity->build(From    => $dirserv_config{'notify_from'},
		To      => $peer,
		Subject => "new alias",
		Type    => "multipart/mixed");

		$top->attach(Path => $name);

	
		open (SENDMAIL, "|/kolab/sbin/sendmail -oi -t -odq") or 
			die "Can't fork for sendmail: $!\n";
		$top->print(\*SENDMAIL);
		close SENDMAIL or warn "sendmail didn't close properly";
		print "New alias notification sent to: $peer\n";
	}
	$fh->close();


}

sub notify_modify_alias {
	my $notify = shift;
	my $entry = $notify->clone;

	#If no peers, ignore the request
	if (length(@addressbook_peers) == 0) { return 0 };
	
	#Clean up some unwanted attributes
	$entry->delete('userpassword');
	$entry->delete('uid');
	#$entry->delete('alias');

	#Set up temporary file
	do { $name = tmpnam() }
		until $fh = IO::File->new($name, O_RDWR|O_CREAT|O_EXCL);

	#Write our LDAP entry to temp file in LDIF format
	my $ldif = Net::LDAP::LDIF->new( $fh, "r", onerror => 'undef' );
	$ldif->write_entry($entry);

	foreach my $peer (@addressbook_peers) {
		#Seek to the beginning of the temp file
		seek ($fh,0,0);

		my $top = MIME::Entity->build(From    => $dirserv_config{'notify_from'},
		To      => $peer,
		Subject => "modify alias",
		Type    => "multipart/mixed");

		$top->attach(Path => $name);

	
		open (SENDMAIL, "|/kolab/sbin/sendmail -oi -t -odq") or 
			die "Can't fork for sendmail: $!\n";
		$top->print(\*SENDMAIL);
		close SENDMAIL or warn "sendmail didn't close properly";
		print "New alias notification sent to: $peer\n";
	}
	$fh->close();


}
#Send a notification to remove alias to peers
sub notify_remove_alias {
	my $notify = shift;

	foreach my $peer (@addressbook_peers) {
		#Seek to the beginning of the temp file

		my $top = MIME::Entity->build(From    => $dirserv_config{'notify_from'},
		To      => $peer,
		Subject => "remove alias",
		Type    => "multipart/mixed");
	
		$top->attach(Data=> ["dn : ".$notify->dn."\n",
				     "mail : ".$notify->get_value('mail')."\n",
				     "cn : ".$notify->get_value('cn')."\n"
		]);
			
		open (SENDMAIL, "|/kolab/sbin/sendmail -oi -t -odq") or 
			die "Can't fork for sendmail: $!\n";
		$top->print(\*SENDMAIL);
		close SENDMAIL or warn "sendmail didn't close properly";
		print "Remove alias notification sent to: $peer\n";
	}
}

sub handle_notifications {
	my $server = shift;
	my $user = shift;
	my $password = shift;

	my $imap = Mail::IMAPClient->new( Server => $server,
					  User   => $user,
					  Port   => 143,
					  Password => $password,
					  Peek => 1) || die "Cannot connect: $@";

	$imap->Status || die "Cannot connect: $@";

	my $ldapuri = URI->new($kolab_config{'ldap_uri'}) || die "error: could not parse given uri";
	my $ldap = Net::LDAP->new($ldapuri->host, port=> $ldapuri->port) || die "could not connect ldap server";

	$ldap->bind($kolab_config{'bind_dn'}, password=> $kolab_config{'bind_pw'}) || die "could not bind to ldap";

	my $parser = new MIME::Parser;

	# Use IDLE instead of polling
	my @folders = $imap->folders;

	foreach my $folder (@folders){
		next if $folder =~ /^\./;
		$imap->select($folder);

		my @messagelist = $imap->search('UNDELETED');	
		foreach my $message (@messagelist) {
			my $data = $imap->message_string($message);
			warn "Empty message data for $folder/$message" unless defined $data && length $data;
			
			$parser->output_under("/tmp");
			my $entity = $parser->parse_data($data);
			my $subject = $entity->head->get('Subject',0);	
			$subject = trim($subject);
			
			#Sanity check
			if ($subject =~ /new alias/ && $entity->is_multipart) {
				#print $entity->parts;
				my ($name,$fh);
				my $part = $entity->parts(0);
				my $bodyh = $part->bodyhandle;
				do { $name = tmpnam() }
					until $fh = IO::File->new($name, O_RDWR|O_CREAT|O_EXCL);
		
				$bodyh->print(\*$fh);
				seek($fh,0,0);

				my $ldif = Net::LDAP::LDIF->new( $fh, "r", onerror => 'undef' );
				while ( not $ldif->eof() ) {
					my $entry = $ldif->read_entry();
					my $cn = $entry->get_value('cn'); #,".$kolab_config{'bind_dn'});
					$cn = trim($cn);
					$cn = "cn=$cn".",cn=external,".$kolab_config{'base_dn'};
					$entry->dn($cn);
								 
					if ( !$ldif->error() ) {
						foreach my $attr ($entry->attributes) {
							#print $attr,"\n";
							my $value = $entry->get_value($attr);
							$value = trim($value);
							$entry->replace($attr,$value);
							#print join("\n ",$attr, $entry->get_value($attr)),"\n";
						}
						my $result = $entry->update($ldap);
						$result->code && warn "failed to add entry: ", $result->error ;
					}
					print "$subject ",$entry->dn(),"\n";
				}
				$fh->close();		
			} elsif ($subject =~ /modify alias/ && $entity->is_multipart) {
				#print $entity->parts;
				my ($name,$fh);
				my $part = $entity->parts(0);
				my $bodyh = $part->bodyhandle;
				do { $name = tmpnam() }
					until $fh = IO::File->new($name, O_RDWR|O_CREAT|O_EXCL);
		
				$bodyh->print(\*$fh);
				seek($fh,0,0);

				my $ldif = Net::LDAP::LDIF->new( $fh, "r", onerror => 'undef' );
				while ( not $ldif->eof() ) {
					my $entry = $ldif->read_entry();
					my $cn = $entry->get_value('cn'); #,".$kolab_config{'bind_dn'});
					$cn = trim($cn);
					$cn = "cn=$cn".",cn=external,".$kolab_config{'base_dn'};
					$entry->dn($cn);
					$entry->changetype('modify');
								 
					if ( !$ldif->error() ) {
						foreach my $attr ($entry->attributes) {
							#print $attr,"\n";
							my $value = $entry->get_value($attr);
							$value = trim($value);
							$entry->replace($attr,$value);
							#print join("\n ",$attr, $entry->get_value($attr)),"\n";
						}
						my $result = $entry->update($ldap);
						if ($result->code) { 
						        warn "failed to add entry: ", $result->error ; 
							$entry->changetype('add');
							$result = $entry->update($ldap);
							$result->code && warn "failed to add entry: ", $result->error ;
						}
					}
					print "$subject ",$entry->dn(),"\n";
				}
				$fh->close();			
			} elsif ($subject =~ /remove alias/ && $entity->is_multipart) {
				#print $entity->parts;
				my ($name,$fh);
				my $part = $entity->parts(0);
				my $bodyh = $part->bodyhandle;
				#trim($bodyh);
				#print $bodyh;
				my $IO = $bodyh->open("r")      || die "open body: $!";
				while (defined($_ = $IO->getline)) {
					my $line = $_;
					$line = trim($line);
					if (/(.*) : (.*)/) { 
						if ($1 eq "cn") {
							my $cn = trim($2);
							print "cn=$cn,cn=external,".$kolab_config{'base_dn'},"\n";
							my $result = $ldap->delete("cn=$cn,cn=external,".$kolab_config{'base_dn'});
							$result->code && warn "failed to delete entry: ", $result->error ;
						}
					}
				}
				$IO->close                  || die "close I/O handle: $!";
				print $subject,"\n";
			}
			
			
		}
		$imap->set_flag("Deleted",@messagelist);
		$imap->close or die "Could not close :$folder\n";
	}
}



1;
__END__

=head1 NAME

Kolab::DirServ - A Perl Module that handles Address book 
synchronisation between Kolab servers.

=head1 SYNOPSIS

  use Kolab::DirServ;
  use Net::LDAP::Entry;
 
  #send notification of a new mailbox
  $entry = Net::LDAP::Entry->new(...);
  &notify_new_alias( $entry );
  
  #handle updates recieved
  &handle_notifications( "address", "IMAP User", "User Password" );

=head1 ABSTRACT

  The Kolab::DirServ module provides a mechanism for Kolab servers to
  publish address book data to a list of peers. These peers recieve
  notification of new, updated and removed mailboxes and update their
  address books accordingly.
  
=head1 DESCRIPTION

The Kolab::DirServ module recieves Net::LDAP::Entry entries, converts
them to LDIF format and sends them to a list of mailboxes in LDIF 
format.
The list of peers and other configuration parameters is provided 
through the Kolab::DirServ::Config module. 

=head2 EXPORT
	
  &notify_new_alias( $entry )

    Recieves a Net::LDAP::Entry object.
    Send a new alias notification to each of the address book peers in
    a LDIF MIME attachment.
  
  &notify_remove_alias( $entry )
 
    Recieves a Net::LDAP::Entry object.
    Send a notification to each of the address book peers to remove an
    entry from their address books.
  
  &notify_modify_alias( $entry )

    Recieves a Net::LDAP::Entry object.
    Send updated information to each of the address book peers. Each
    peer then updates the corresponding address book entry with the 
    updated information.

  &handle_notifications( $server, $user, $password )

    Connects to specified IMAP server and retrieves all messages from
    the specified mailbox. The messages are cleared from the mailbox 
    after they are handled. This process runs periodically on a peer.

=head1 SEE ALSO

kolab-devel mailing list: <kolab-devel@lists.intevation.org>

Kolab website: http://kolab.kroupware.org

=head1 AUTHOR

Stephan Buys, s.buys@codefusion.co.za

Please report any bugs, or post any suggestions, to the kolab-devel
mailing list <kolab-devel@lists.intevation.de>.
       

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Stephan Buys

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
