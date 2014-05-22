class MuseicController < ApplicationController
  def index
    @plays  = Play.order('recent DESC').limit(20)
  end
end
