#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:

package Rex::Virtualization::VBox::start;

use strict;
use warnings;

use Rex::Logger;
use Rex::Commands::Run;
use Rex::Commands::File;
use Rex::Commands;
use Cwd 'getcwd';

sub execute {
   my ($class, $arg1, %opt) = @_;

   unless($arg1) {
      die("You have to define the vm name!");
   }

   my $dom = $arg1;
   Rex::Logger::debug("starting domain: $dom");

   unless($dom) {
      die("VM $dom not found.");
   }

   my $virt_settings = Rex::Config->get("virtualization");
   my $headless = 0;
   if(ref($virt_settings)) {
      if(exists $virt_settings->{headless} && $virt_settings->{headless}) {
         $headless = 1;
      }
   }

   if($headless && $^O =~ m/^MSWin/ && ! Rex::is_ssh()) {
      Rex::Logger::info("Right now it is not possible to run VBoxHeadless under Windows.");
      $headless = 0;
   }

   if($headless) {
      my $filename = "/tmp/" . get_random(8, 'a' .. 'z') . ".tmp";

      file("$filename",
         content => <<EOF);
use POSIX();

my \$pid = fork();
if (defined \$pid && \$pid == 0 ) {
   # child
   chdir "/";
   umask 0;
   POSIX::setsid();
   local \$SIG{'HUP'} = 'IGNORE';
   my \$spid = fork();
   if (defined \$spid && \$spid == 0 ) {

      open( STDIN,  "</dev/null" );
      open( STDOUT, "+>/dev/null" );
      open( STDERR, "+>/dev/null" );

      # 2nd child
      unlink "$filename";
      exec("VBoxHeadless --startvm \\\"$dom\\\"");
      exit;


   }

   exit; # end first child (2nd parent)
}
else {
   waitpid( \$pid, 0 );
}

exit;

EOF

      run "perl $filename";
   }
   else {
      run "VBoxManage startvm \"$dom\"";
   }

   if($? != 0) {
      die("Error starting vm $dom");
   }

}

1;
