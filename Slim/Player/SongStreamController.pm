package Slim::Player::SongStreamController;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use bytes;
use strict;
use warnings;

use Slim::Utils::Log;

my $log = logger('player.source');

my $_liveCount = 0;

sub new {
	my ($class, $song, $streamHandler) = @_;

	my $self = {
		song => $song,
		streamHandler => $streamHandler,
		protocolHandler => my $handler = Slim::Player::ProtocolHandlers->handlerForURL($song->{'streamUrl'}),
	};

	bless $self, $class;
	
	$_liveCount++;
	if ($log->is_debug) {
		$log->debug("live=$_liveCount");	
	}
	
	return $self;
}

sub DESTROY {
	my $self = shift;
	
	$self->close();
	
	$_liveCount--;
	if ($log->is_debug)	{
		$log->debug("live=$_liveCount");
	}
}

sub song {return shift->{'song'};}
sub streamHandler {return shift->{'streamHandler'};}
sub protocolHandler {return shift->{'protocolHandler'};}

sub songProtocolHandler {return shift->song()->{'handler'};}

sub close {
	my $self = shift;
	
	if ($self->{'streamHandler'}) {
		$self->{'streamHandler'}->close;
		delete $self->{'streamHandler'};
	}
}

sub isDirect {
	return shift->{'song'}->{'directstream'} || 0;
}

sub streamUrl {
	return shift->{'song'}->{'streamUrl'};
}

sub track {
	return shift->{'song'}->currentTrack();
}


1;
