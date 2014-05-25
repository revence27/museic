# encoding: utf-8
# charset: utf-8
class MuseicController < ApplicationController
  def index
    @plays  = MuseicSong.order('last_play DESC').limit(20)
  end
end
