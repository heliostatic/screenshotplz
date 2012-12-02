require 'bundler/setup'
require 'sinatra'
require 'sinatra/synchrony'
require 'digest/sha1'
require 'mini_magick'

use Rack::CommonLogger
set :static_cache_control, [:public, :max_age => 86400]
Fiber.new {
  configure :production do
    require 'newrelic_rpm'
  end
}.resume

get %r{/(\d+x\d+)/(.+)} do
  url = params[:captures].last
  url.sub!(%r{:/(\w)}, '://\1')
  url = %r{^https?://}.match(url) ? url : 'http://' + url
  width, height = params[:captures].first.split('x')
  filename = image_filename(url)
  if File.exists?(File.join('public', filename))
    redirect filename
  end
  halt 500 unless EM::Synchrony.popen("phantomjs rasterize.js #{url} #{width} #{height} public#{filename}")
  pre_proc_image = File.open(File.join('public', filename), 'r')
  image = MiniMagick::Image.read(pre_proc_image)
  image.resize "250x195"
  image.write  "public#{filename}"
  redirect filename
end

get '/weather/:city' do
  filename = image_filename(params[:city])
  halt 404 unless EM::Synchrony.popen "phantomjs weather.coffee \"#{params[:city]}\" public/#{filename}"
  redirect filename
end

def image_filename(str)
  '/' + Digest::SHA1.hexdigest("v4-#{str}") + '.png'
end

class PopenHandler < EM::Connection
  include EM::Deferrable

  def receive_data(data)
  end

  def unbind
    succeed(get_status.exitstatus == 0)
  end
end

module EventMachine
  module Synchrony
    def self.popen(cmd, *args)
      df = nil
      EM.popen(cmd, PopenHandler, *args) { |conn| df = conn }
      EM::Synchrony.sync df
    end
  end
end
