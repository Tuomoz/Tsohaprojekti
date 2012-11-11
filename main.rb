require 'sinatra'
require "sinatra/reloader"
require "sequel"
require "haml"
require 'rack-flash'


DB = Sequel.connect('sqlite://testdb')
use Rack::Flash

configure do
  enable :sessions
end

helpers do
  def logged_in?
    session[:user] != nil
  end

  def get_nav_class path
    if request.path_info == path
      "active"
    else
      ""
    end
  end
end

get "/" do
  if params.has_key?("logout")
    session.clear
  end
  haml :index
end

post "/" do

  user = DB.fetch("SELECT id FROM users WHERE username = ? AND password = ?", 
                  params[:username], params[:password]).first

  if user
    session[:user] = user[:id]
    redirect "/user"
  else
    flash[:status_msg] = :login_error
    redirect "/"
  end
end

get "/user" do
  if logged_in?
    haml :user
  else
    redirect "/"
  end
end