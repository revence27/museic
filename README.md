Muse-ic
=======
A specialised streaming system for audio Bibles, where the readings are interspersed with music.

Usage:
-----

  ruby museic.rb 8888 dir/readings/playlist.m3u dir/music/playlist.m3u

The M3U files can be as many as you have, and the system will read from the first and stream it, then the next, then the next … and so on. When randomised with variables (see below), it still follows this order, but streams files from the individual playlists at random.

Variables:
---------
When the environment variable RANDOM\_MUSEIC is set to 'random', it makes the system select randomly from the playlists.
