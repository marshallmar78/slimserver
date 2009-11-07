#!/usr/bin/perl
#
# Stand-alone interface to ImageResizer
#
# TODO:
# Better error handling
#

use strict;

use constant RESIZER      => 1;
use constant SLIM_SERVICE => 0;
use constant PERFMON      => 0;
use constant SCANNER      => 0;
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant DEBUG        => ( grep { /--debug/ } @ARGV ) ? 1 : 0;

BEGIN {
	use Slim::bootstrap ();
	Slim::bootstrap->loadModules( ['GD'], [] );
};

use Getopt::Long;

use Slim::Utils::ImageResizer;

my $help;
our ($file, $url, @spec, $cacheroot, $cachekey, $faster, $debug);

my $ok = GetOptions(
	'help|?'      => \$help,
	'file=s'      => \$file,
	'url=s'       => \$url,
	'spec=s'      => \@spec,
	'cacheroot=s' => \$cacheroot,
	'cachekey=s'  => \$cachekey,
	'faster'      => \$faster,
	'debug'       => \$debug,
);

if ( !$ok || $help || ( !$file && !$url ) || !@spec ) {
	require Pod::Usage;
	Pod::Usage::pod2usage(1);
}

# Download URL to a temp file
my $fh;
if ( $url ) {
	require File::Temp;
	require LWP::UserAgent;
	
	$fh = File::Temp->new();
	$file = $fh->filename;
	
	my $ua = LWP::UserAgent->new( timeout => 5 );
	
	$debug && warn "Downloading URL to $file\n";
	
	my $res = $ua->get( $url, ':content_file' => $file );
	
	if ( !$res->is_success ) {
		die "Unable to download $url: " . $res->status_line . "\n";
	}
}

# Setup cache
my $cache;
if ( $cacheroot && $cachekey ) {
	require Cache::FileCache;
	
	$cache = Cache::FileCache->new( {
		namespace       => 'Artwork',
		cache_root      => $cacheroot,
		directory_umask => umask(),
	} );
}

if ( @spec > 1 ) {
	# Resize in series
	
	# Construct spec hashes
	my $specs = [];
	for my $s ( @spec ) {
		my ($width, $height, $mode) = $s =~ /^([^x]+)x([^_]+)_(\w)$/;
		
		if ( !$width || !$height || !$mode ) {
			die "Invalid spec: $s\n";
		}
		
		push @{$specs}, {
			width  => $width,
			height => $height,
			mode   => $mode,
		};
	}
		
	my $series = eval {
		Slim::Utils::ImageResizer->resizeSeries(
			file   => $file,
			debug  => $debug,
			faster => $faster,
			series => $specs,
		);
	};
	
	if ( $@ ) {
		die "$@\n";
	}
	
	if ( $cacheroot && $cachekey ) {
		for my $s ( @{$series} ) {
			my $width  = $s->[2];
			my $height = $s->[3];
			my $mode   = $s->[4];
			
			my $ct = 'image/' . $s->[1];
			$ct =~ s/jpg/jpeg/;
		
			# Series-based resize has to append to the cache key
			my $key = $cachekey;
			$key .= "${width}x${height}_${mode}";
		
			_cache( $key, $s->[0], $ct );
		}
	}
}
else {
	my ($width, $height, $mode, $bgcolor, $ext) = $spec[0] =~ /^([^x]+)x([^_]+)(?:_(\w))?(?:_([\da-fA-F]+))?\.?(\w+)?$/;
	
	if ( !$width || !$height ) {
		die "Invalid spec: $spec[0]\n";
	}
	
	# XXX If cache is available, pull pre-cached size values from cache
	# to see if we can use a smaller version of this image than the source
	# to reduce resizing time.
	
	my ($ref, $format) = eval {
		Slim::Utils::ImageResizer->resize(
			file    => $file,
			debug   => $debug,
			faster  => $faster,
			width   => $width,
			height  => $height,
			mode    => $mode,
			bgcolor => $bgcolor,
			format  => $ext,
		);
	};
	
	if ( $@ ) {
		die "$@\n";
	}
	
	if ( $cacheroot && $cachekey ) {
		my $ct = 'image/' . $format;
		$ct =~ s/jpg/jpeg/;
		
		# When doing a single resize, the cachekey passed in is all we store
		
		_cache( $cachekey, $ref, $ct );
	}
}

exit 0;

sub _cache {
	my ( $key, $imgref, $ct ) = @_;
	
	my $cached = {
		orig        => $file,
		mtime       => (stat $file)[9],
		size        => length($$imgref),
		body        => $imgref,
		contentType => $ct,
	};

	$cache->set( $key, $cached, $Cache::Cache::EXPIRES_NEVER );
	
	$debug && warn "Cached $key (" . $cached->{size} . " bytes)\n";
}

__END__

=head1 NAME

gdresize.pl - Standalone artwork resizer

=head1 SYNOPSIS

Resize normal image file or an audio file's embedded tags:

Options:

  --file [ /path/to/image.jpg | /path/to/image.mp3 ]
    Supported file types:
      Images: jpg, jpeg, gif, png
      Audio:  see Audio::Scan documentation

  --url http://...

  --spec <width>x<height>_<mode>[.ext] ...
    Mode is one of:
	  m: max         (default)
	  p: pad         (same as max)
	  s: stretch
	  S: squash
	  f: fitstretch
	  F: fitsquash
	  c: crop
	  o: original
	
	Multiple spec arguments may be specified to resize in series.

  --faster                 Use ugly but fast copyResized function
  --cacheroot [dir]        Cache resulting image in a FileCache called
                           'Artwork' located in dir
  --cachekey [key]         Use this key for the cached data.
                           Note: spec value will be appended to the cachekey
                           if multiple spec values were supplied.

=cut