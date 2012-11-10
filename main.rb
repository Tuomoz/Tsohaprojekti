require 'sinatra'
require "sinatra/reloader"
require "sequel"

configure do
  enable :sessions
end

get '/' do  
  haml :index
end