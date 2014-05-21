EXTRA=~/Desktop/Misc/Muze/much-music.m3u

test:
	ruby museic.rb 8888 ~/Desktop/Misc/{Muze,Luganda}/playlist.m3u $(EXTRA)

much:
	ruby museic.rb 8888 ~/Desktop/Misc/{Muze,Luganda,Muze}/playlist.m3u

nice:
	ruby museic.rb 8888 ~/Desktop/Misc/{Muze,Luganda}/playlist.m3u

bible:
	ruby museic.rb 8888 ~/Desktop/Misc/Luganda/playlist.m3u
