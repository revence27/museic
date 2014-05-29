# encoding: utf-8
# charset: utf-8
class MuseicController < ApplicationController
  def index
    @plays  = MuseicSong.order('last_play DESC').limit(20)
  end

  def dloader
    fich  = AlbumArt.where('sha1_sig = ?', [request[:sha]]).first
    if not fich then
      render status: 404, text: ''
    else
      if request.headers['If-None-Match'] then
        render status: 304, text: ''
      else
        response.headers['Content-Type']  = fich.content_type
        response.headers['ETag']          = fich.sha1_sig
        render status: 200, text: fich.rawdata
      end
    end
  end
end
