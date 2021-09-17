#!/usr/bin/perl
use warnings;
use strict;
use Cwd;
use File::Basename;
use File::Spec;
use Getopt::Long 'HelpMessage';
use URI::Encode;
use XML::Twig;
use utf8::all;

# process command-line arguments
my $dry_run;
GetOptions(
  'dry-run'      => \$dry_run,
  'help'        => sub { HelpMessage(0) }
  ) or HelpMessage(1);

# get input maps to process (default is dita/*.ditamap)
my @input_map_files = distinct(map {File::Spec->rel2abs($_)} @ARGV);

# read map files and gather metrics
foreach my $map_file (@input_map_files) {
 # read this map
 my $this_map_twig = read_map_twig($map_file) or next;

 # get the keys defined in this map 
 my %keyref_for_href = map {get_abs_href($_) => $_->att('keys')} ($this_map_twig->descendants('*[@href and @keys]'));

 # add root-ID variants so we match non-topic elements inside root topic elements
 foreach my $dita_file (grep {-f $_} grep {$_ =~ m!\.dita$!} keys %keyref_for_href) {
  if (my ($root_element) = (read_entire_file($dita_file) =~ m!(<\w[^>]*>)!)) {
   if (my ($id) = ($root_element =~ m!id="([^"]+)"!)) {
    $keyref_for_href{"${dita_file}#${id}"} = $keyref_for_href{$dita_file};
   }
  }
 }

 # loop through the topic files used by this map
 my @dita_files = grep {-f $_} distinct(map {get_abs_href($_) =~ s!\#.*$!!r} $this_map_twig->descendants('*[@href =~ /\.dita($|#)/]'));
 my $map_changed = 0;
 foreach my $dita_file (@dita_files) {
  my $topic_guts = read_entire_file($dita_file);
  my $file_changed = 0;

  # this subroutine is called for each regsub match of 'href="..."'
  my $process_href = sub {
   my $href_tag = shift;
   my ($href) = ($href_tag =~ m!"([^"]+)"!);
   $href = URI::Encode::uri_decode($href) if $href =~ m!%!;  # too slow to do it all the time
   if (my ($topic, $nontopic) = ($href =~ m!^(.*?\.dita(?:#[^\/]+)?)(\/.*)?$!)) {
    # path/file.dita#topicid/otherid
    # ^^^^^^^^^^^^^^^^^^^^^^         - $topic
    #                       ^^^^^^^^ - $nontopic
    $topic = File::Spec->rel2abs($topic, dirname($dita_file));
    while ($topic =~ s![^/]+/\.\./!!) {}  # collapse dir1/../dir2 backtracking
    if (exists($keyref_for_href{$topic})) {
     $file_changed++;
     return sprintf('keyref="%s%s"', $keyref_for_href{$topic}, ($nontopic or ''));
    }
   }
   return $href_tag;  # leave as-is
  };

  # process all @hrefs
  $topic_guts =~ s!(?<=\s)(href="[^"]+")!$process_href->($1)!gse;

  # write file if changed
  if ($file_changed) {
   write_entire_file($dita_file, $topic_guts) unless $dry_run;
   $map_changed++;
  }
 }
 print "Updated $map_changed topics in '".File::Spec->abs2rel($map_file)."'.\n" if $map_changed;
}

exit;



####
## HELPER SUBROUTINES
##

# read entire file into a string
sub read_entire_file {
 my $filename = shift;
 open(FILE, "<$filename") or die "can't open $filename for read: $!";
 local $/ = undef;
 binmode(FILE, ":encoding(utf-8)");  # the UTF-8 package checks and enforces this
 my $contents = <FILE>;
 close FILE;
 return $contents;
}

# write string to a file
sub write_entire_file {
 my ($filename, $contents) = @_;
 $contents =~ s!\n?$!\n!s;  # add LF if needed
 open(FILE, ">$filename") or die "can't open $filename for write: $!";
 binmode(FILE);  # don't convert LFs to CR/LF on Windows
 binmode(FILE, ":encoding(utf-8)");  # the UTF-8 package checks and enforces this
 print FILE $contents;
 close FILE;
}

# return sorted, unique list of values
sub distinct {
 my %values = map {$_ => 1} @_;
 return sort keys %values;
}

# convert a relative @href to an absolute path
sub get_abs_href {
 my $elt = shift;
 my $dir = dirname($elt->inherit_att('file'));
 my $href = File::Spec->rel2abs($elt->att('href'), $dir);
 $href = URI::Encode::uri_decode($href) if $href =~ m!%!;  # too slow to do it all the time
 while ($href =~ s![^/]+/\.\./!!) {}
 return $href;
}

# read a map, inlining submaps as needed
sub read_map_twig {
 my $this_map_file = shift;
 if ( !-f $this_map_file ) {
  print STDERR "Warning: Could not find file '".File::Spec->abs2rel($this_map_file)."'.\n";
  return undef;
 }
 my $this_map_dir = dirname($this_map_file);
 my $this_map_twig = XML::Twig->new(
  start_tag_handlers => {
   '/*' => sub { $_->set_att('file', $this_map_file); return 1; },
  },
  twig_handlers => {
   '*[@href =~ /\.ditamap$/ and @scope != "peer"]' => sub {
    my $submap_file = get_abs_href($_);  # inline submap file
    if (my $submap = read_map_twig($submap_file)) {
     # if there are keyscopes on the submap reference, merge them with any map-level keyscopes
     if (defined(my $map_keyscopes = $_->att('keyscope'))) {
      my @mapref_keyscopes = split(/\s+/, $map_keyscopes);
      my @submap_keyscopes = split(/\s+/, ($submap->root->att('keyscope') or ''));
      $submap->root->set_att('keyscope', join(' ', distinct(@mapref_keyscopes, @submap_keyscopes)));
     }
     $_->replace_with($submap->root->cut);
    } else {
     $_->set_att('#notfound', 1);
    }
   },
  })->safe_parsefile($this_map_file);
 if (!$this_map_twig) {
  print STDERR "Warning: Could not process map file '".File::Spec->abs2rel($this_map_file)."'.\n";
  return undef;
 }

 return $this_map_twig;
}


__END__

=head1 NAME

convert_hrefs_to_keyrefs.pl - convert href cross-references to .dita files to keyref

=head1 SYNOPSIS

  [map1.ditamap [...]]
       DITA maps to process
  --dry-run
        Process but don't modify files

=cut

