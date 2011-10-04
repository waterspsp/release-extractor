#!/usr/bin/perl
# - Automatic movie/tv release extraction, naming and placement
# - Written by BoogieManTM Oct 03rd, 2011
# - boogieman@twistedmindz.net
# 
# --------
# - TODO:
# - Add handling for multi-part video (cd1/cd2/cd3, etc) and hopefully auto-merge them!
# - Metadata perhaps?
# - Label support
# - Multiple source/formats - prefer 1080p? 720p? dvdr? dvdrip?
# - Config file support


use strict;
use warnings;
use IMDB::Film;
use Getopt::Long;
use File::Path qw(make_path);
use File::Basename;
use String::Similarity;
use Cwd;

my $current_dir = getcwd;


# save path will dump in:
# Movies: $base_path/Movies/Movie Name (Year)/Movie File.ext(s)
# TV Shows: $base_path/Television/Show Name/Season #/Show Name s[xx]e[yy] - Episode Name.ext(s)
my $save_path = "G:\\sorted\\";

# IMDB cache directory
my $imdb_cache = $current_dir . "/.imdb_cache/";

# Global exception
# Release names that match these days WILL get IGNORED!
# I got tired of matching these: House.Season.1.Extras.DVDRip.XviD-CRT
# Screw extra's, anyways!

my $global_exclusion = "extras|subpack";


# rar setup
# Path and parameters
my $winrar_path = "C:\\Program Files\\WinRAR\\Rar.exe";
# ; delimited list of extensions to extract (ONLY THESE EXTENSIONS GET EXTRACTED!)
# Remove the -ms parameter below to disable this and extract-all
my $winrar_extensions = "3gp;asf;avi;flv;m1s;m1v;m2s;m2v;m4v;mkv;mov;mp2v;mp4;mpe;mpeg;mpg;ogg;ogm;qt;sub;wmv";
my $winrar_params = "e -cl -ep -ed -mt2 -ms[$winrar_extensions] -o- -r -ri4 -tk";



my $tv_tags = "proper|rerip|reup|repack|720p|1080p|complete|LiMiTED|iNTERNAL|WS|subfix";
my $tv_sources = "hdtv|pdtv|sdtv|tvrip|dvb|dsr|ppv|dvdrip|bdrip|dvdr|pal|ntsc|bluray";
my $movie_tags = "COMPLETE|LiMiTED|STV|FESTiVAL|iNTERNAL|Subbed|extended|rated|FiX|rerip|reup|proper|repack|720p|1080p";
my $movie_sources = "DVDRip|NTSC|BluRay|PAL|BDRip|DVDSCR|BRSCR|mixed";
my $format_tags = "xvid|x264|dvdr|bdr|ac3";



##########################################################
#            EDIT BELOW AT YOUR OWN RISK!                #
##########################################################















my $name;
my $directory;

GetOptions ("name=s" => \$name, #str
            "dir=s" => \$directory); #str


if (!defined $name || !defined $directory) 
{
    print "This script must be passed a name and directory to look for a release!\n";
    die "$0 --name Release.Example.Name.SE.1080p.BluRay.X264-GROUP --dir \"C:/Downloads/Torrents/Release.Example.Name.SE.1080p.BluRay.X264-GROUP\"\n\n";
}

use constant false => 0;
use constant true  => 1;

if ($name =~ /$global_exclusion/i) 
{
	print "$name matches global exclusion list: $global_exclusion -- IGNORED!\n";
	exit();
}

my %root_torrent = %{LoadReleaseDetails($name, $directory)};


if (!$root_torrent{'full_season'} && !$root_torrent{'is_pack'}) 
{
    ExtractOne(\%root_torrent);
}
else
{
    ExtractMany(\%root_torrent);
}


sub ExtractOne
{
    my %cur_torrent = %{$_[0]};
    my $target_directory = $save_path;

    my $filename;
    
    if ($cur_torrent{'is_tv'}) 
    {
        $filename = ($cur_torrent{'imdb_name'} || $cur_torrent{'clean_name'});
        $target_directory .= sprintf("Television\\%s\\Season %d\\", ($cur_torrent{'imdb_name'} || $cur_torrent{'clean_name'}), $cur_torrent{'season'});
        $filename .= sprintf(" S%02dE%02d", $cur_torrent{'season'}, $cur_torrent{'episode'});
        $filename .= sprintf(" - %s", $cur_torrent{'episode_title'}) if ($cur_torrent{'episode_title'});
    }
    elsif($cur_torrent{'is_movie'})
    {
        $target_directory .= sprintf("Movies\\%s (%d)\\", ($cur_torrent{'imdb_name'} || $cur_torrent{'clean_name'}), $cur_torrent{'year'});
    }

    my $rars = GetRarsForDirectory($cur_torrent{'original_path'});
    my @dirs = keys %{$rars};

    print "Recursively found " . ($#dirs+1) . " directories with rars\n";
    foreach my $dir (@dirs) 
    {
        my $count = $#{$rars->{$dir}} + 1;
        next if ($count == 0);

		my $lastrar;

        #print "A total of: " . $count. " rar(s) found in: $dir\n";
        for (my $i = 0; $i < $count; $i++) 
        {
			if (defined $lastrar) 
			{
				my $file_score = similarity(lc($lastrar), lc(${$rars->{$dir}}[$i]));

				if ($file_score < 0.91) 
				{
					print "New rar file!\n";
				}
				elsif ($file_score > 0.90 && $file_score != 1.0)
				{
					print "RAR too similar (multi-part .rar?) - skipping!\n";
					next;
				}
				else
				{
					print "Same RAR as last run! Skipping. \n";
					next;
				}

			}

            print "Extracting RAR #".$i.": ". fileparse(${$rars->{$dir}}[$i]) . "\n";
			$lastrar = ${$rars->{$dir}}[$i];
            ExtractRar(${$rars->{$dir}}[$i], $target_directory, $filename);
        }
    }
	print "\n\nDone with ". $cur_torrent{'original_name'} . "\n\n";
}

sub ExtractMany
{
    my %base_torrent = %{$_[0]};
    
	print "Mass extracting: $base_torrent{original_name}\n";

    my @sub_directories = GetDirectories($base_torrent{'original_path'});


    foreach my $dir (@sub_directories) 
    {
        my $child_directory = $dir;
        $dir =~ s!(/|\\)$!!;
        my $child_name = fileparse($dir);

		if ($child_name =~ /$global_exclusion/i) 
		{
			print "\n\n$child_name matches global exclusion list: $global_exclusion -- IGNORED!\n\n";
			next;
		}

        print "Dir: $child_directory - Name: $child_name\n";
        my $child_tor_ref = LoadReleaseDetails($child_name, $child_directory);
        
        # Multi-Season torrent. go one level deeper per season
        if ($base_torrent{'season'} =~ /\d+\-\d+/) 
        {
            ExtractMany($child_tor_ref);
        }
        else
        {
            ExtractOne($child_tor_ref);
        }
    }
}

sub CleanupName 
{
    my ($original_name) = $_[0];
    $original_name =~ s/[\.\-_]/ /g;
    $original_name =~ s/[(\)\[\]\{\}\"\']//g;
	$original_name =~ s/^\s+//; #remove leading spaces
	$original_name =~ s/\s+$//; #remove trailing spaces
    return $original_name;
}

sub TrimZero
{
    my ($original_number) = $_[0];
    $original_number =~ s/^0//g;
    return $original_number;
}

sub TrimPath 
{
    my ($original_path) = $_[0];
    $original_path =~ s/[\\\/]$//;
    return $original_path;
}

sub GetRarsForDirectory
{
    my ($base_directory) = $_[0];

    my @directories = GetDirectories($base_directory);
	push(@directories, $base_directory);
    my $rars;
    
    foreach my $dir (@directories) {
        push(@{$rars->{$dir}}, GetFiles($dir));
    }
    return $rars;
}

sub GetDirectories 
{
    my ($base_directory) = $_[0];

    my @list;

    opendir(DIR, $base_directory) or die "Unable to open source directory! $!";
    my @files = readdir(DIR);
    closedir(DIR);

    foreach my $file (@files) 
    {
        next if ($file =~ /^\.+$/);

        my $combined = TrimPath($base_directory) . "/" . $file;
        push(@list, $combined) if (-d $combined);
    }
    return @list;
}

sub GetFiles 
{
    my ($base_directory) = $_[0];

    my @list;
    opendir(DIR, $base_directory) or die "Unable to open source directory! $!";
    my @files = readdir(DIR);
    closedir(DIR);

    foreach my $file (@files) 
    {
        next if ($file !~ /rar$/i);

        my $combined = TrimPath($base_directory) . "/" . $file;
        push(@list, $combined) if (-f $combined);
    }
    return @list;
}



sub ExtractRar
{
    my ($source, $target, $newname) = @_;
    my $command = qq~"$winrar_path" $winrar_params "$source" "*" "$target"~;

    chdir($save_path);
    MakeDirectory($target);
    chdir($target);

    my $output = `$command`;

    my ($oldname) = $output =~ m/Extracting\s+\b\Q$target\E(\S+)\b/i;
    print "Done extracting $oldname to $target!\n";

    if (defined $newname) 
    {
        my ($oldext) = $oldname =~ /(\.\S{2,4})$/;
        $newname .= $oldext;

        rename($oldname, $newname);
        print "Renamed file to: $newname\n\n";
    }

}

sub MakeDirectory
{
    my $target = shift;
    make_path($target);
}


sub LoadReleaseDetails
{
    my ($release_name, $release_directory) = @_;
    my %release;

	print "Release:    $release_name\n";
	print "Directory:  $release_directory\n";

    $release{'original_name'} = $release_name;
    $release{'original_path'} = $release_directory;
    $release{'is_movie'} = false;
    $release{'is_pack'} = false;;
    $release{'is_tv'} = false;
    $release{'full_season'} = false;
    $release{'season'} = 0;
    $release{'episode'} = 0;

    # Movie Pack!
    if ($release_name =~ /(.*)\.(?:movies?\.)*pack\.(?:(?<tags>$movie_tags)\.)*(?:(?<sources>$movie_sources)\.)*(?<formats>$format_tags)*.*\-(?<group>\S+)/i)
    {
		print "Movie Pack!\n";
        $release{'name'} = $1;
        $release{'tags'} = $+{tags} if (defined $+{tags});
        $release{'source'} = $+{sources} if (defined $+{sources});
        $release{'format'} = $+{formats} if (defined $+{formats});
        $release{'group'} = $+{group} if (defined $+{group});
        $release{'is_pack'} = true;
        $release{'is_tv'} = false;
    }

    # Season (Multiple?)
    if (!$release{'is_pack'} && $release_name =~ /(.*)\.s?(?<start>\d{1,3})(?:[\. _-]s?(?<end>\d{1,3}))?\.(?:(?<tags>$tv_tags)\.)*(?:(?<sources>$tv_sources)\.)*(?<formats>$format_tags).*\-(?<group>\S+)/i) 
    {
		print "TV Season (possibly multiple)!\n";
        $release{'name'} = $1;
        $release{'season'} = TrimZero($+{start}) if (defined $+{start});
        $release{'season'} .= "-" . TrimZero($+{end}) if (defined $+{end});
        $release{'tags'} = $+{tags} if (defined $+{tags});
        $release{'source'} = $+{sources} if (defined $+{sources});
        $release{'format'} = $+{formats} if (defined $+{formats});
        $release{'group'} = $+{group} if (defined $+{group});
        $release{'is_tv'} = true;
        $release{'full_season'} = true;
    }

	#(.*)\.s?(\d{1,2})[\. _-]?[e|x](\d{1,2})\.(?:.*\.)?(?:(?<tags>$tv_tags)[\._-])*(?:(?<sources>$tv_sources))[\._-])*(?<formats>$format_tags).*[\._-](?<group>\S+)
    # Single Episode
    if (!$release{'is_pack'} && $release_name =~ /(.*)\.s?(\d{1,2})[\. _-]?[e|x](\d{1,2})\.(?:.*\.)?(?:(?<tags>$tv_tags)[\._-])*(?:(?<sources>$tv_sources)[\._-])*(?<formats>$format_tags).*[\._-](?<group>\S+)/i) 
    {
		print "TV Episode!\n";
        $release{'name'} = $1;
        $release{'season'} = TrimZero($2);
        $release{'episode'} = TrimZero($3);
        $release{'tags'} = $+{tags} if (defined $+{tags});
        $release{'source'} = $+{sources} if (defined $+{sources});
        $release{'format'} = $+{formats} if (defined $+{formats});
        $release{'group'} = $+{group} if (defined $+{group});
        $release{'is_tv'} = true;
    }

    # Single Movie?
    if (!$release{'is_pack'} && !$release{'is_tv'}) 
    {
        if ($release_name =~ /(\S+?)(?:\.(?<year>\d{4}))?\.(?:(?<tags>$movie_tags)\.)+(?:(?<sources>$movie_sources)\.)*(?<formats>$format_tags).*\-(?<group>\S+)/i) 
        {
			print "Movie!\n";
            $release{'is_movie'} = true;
            $release{'name'} = $1;
            $release{'year'} = $+{year} if (defined $+{year});
            $release{'tags'} = $+{tags} if (defined $+{tags});
            $release{'source'} = $+{sources} if (defined $+{sources});
            $release{'format'} = $+{formats} if (defined $+{formats});
            $release{'group'} = $+{group} if (defined $+{group});
        }
        # Last ditch effort!
        elsif ($release_name !~ /\d{4}/g && $release_name =~ /(.*)\.(($movie_tags)\.)*(($movie_sources)\.)*(($format_tags)\.).*\-(?<group>\S+)/i)
        {
			print "Movie!\n";
            $release{'name'} = $1;
            $release{'tags'} = $+{tags} if (defined $+{tags});
            $release{'source'} = $+{sources} if (defined $+{sources});
            $release{'format'} = $+{formats} if (defined $+{formats});
            $release{'group'} = $+{group} if (defined $+{group});
            $release{'is_movie'} = true;
            print "Could only get name for movie: ". $release{'name'} ." - \"$release_name\"\n";
        }
    }

    $release{'clean_name'} = CleanupName($release{'name'});


	print "is_movie:        $release{'is_movie'}\n" if (defined $release{'is_movie'});
	print "is_pack:         $release{'is_pack'}\n" if (defined $release{'is_pack'});
	print "is_tv:           $release{'is_tv'}\n" if (defined $release{'is_tv'});
	print "full_season      $release{'full_season'}\n\n" if (defined $release{'full_season'});

	print "media_name:      $release{'name'}\n" if (defined $release{'name'});
	print "clean_name:      $release{'clean_name'}\n" if (defined $release{'clean_name'});
	print "year:            $release{'year'}\n" if (defined $release{'year'});
	print "season:          $release{'season'}\n" if (defined $release{'season'});
	print "episode:         $release{'episode'}\n" if (defined $release{'episode'});
	print "source:          $release{'source'}\n" if (defined $release{'source'});
	print "tags:            $release{'tags'}\n" if (defined $release{'tags'});
	print "format:          $release{'format'}\n" if (defined $release{'format'});
	print "group:           $release{'group'}\n" if (defined $release{'group'});

	if ($release{'is_pack'} == false) 
	{
		print "Querying IMDB for verification\n";

		my $search_str = $release{'clean_name'};
		$search_str .= " " . $release{'year'} if (exists $release{'year'});
		if (!-e $imdb_cache) {
			MakeDirectory($imdb_cache);
		}
		my $imdb = new IMDB::Film(crit => $search_str, debug => 0, timeout => 10, cache=> 1, cache_root=> $imdb_cache, cache_exp => '1 d');

		if($imdb->status) 
		{
			$release{'imdb_name'} = CleanupName($imdb->title());
			$release{'type'} = $imdb->kind();
			$release{'year'} = $imdb->year();
			print "IMDB Title: ".$imdb->title()."\n";
			print "IMDB Year: ".$imdb->year()."\n";
			print "IMDB Type: ".$imdb->kind()."\n";
			if ($release{'type'} =~ /tv/ && $release{'season'} !~ /\d+\-\d+/) 
			{
				foreach my $ep (@{ $imdb->episodes() }) 
				{
					if ($release{'season'} == $ep->{'season'} 
						&& $release{'episode'} == $ep->{'episode'}) 
					{
						$release{'episode_title'} = CleanupName($ep->{'title'});
						$release{'air_date'} = $ep->{'date'};
						print "IMDB Episode: s0". $ep->{'season'} . "e". $ep->{'episode'}. "\n";
						print "IMDB Episode Title: " . $ep->{'title'} . "\nIMDB Air Date: " . $ep->{'date'} . "\n";
					}
				}
			}
			print "\n";
		}
	}

    return (\%release);
}