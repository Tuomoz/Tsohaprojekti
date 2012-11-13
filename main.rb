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
    times = DB.fetch("SELECT * FROM times WHERE user_id = ?", session[:user])
    haml :user, locals: {times: times}
  else
    flash[:status_msg] = :need_login
    redirect "/"
  end
end

post "/addtime" do
  unless logged_in?
    flash[:status_msg] = :need_login
    redirect "/"
  end

  insert_ds = DB["INSERT INTO times VALUES (null, ?, ?, ?, ?)", 
                params[:date], params[:time_start], params[:time_end], session[:user]]
  insert_ds.insert
  flash[:status_msg] = :time_added
  redirect "/user"
end

get "/deletetime/:timeid" do
  unless logged_in?
    flash[:status_msg] = :need_login
    redirect "/"
  end

  delete_ds = DB["DELETE FROM times WHERE id = ? AND user_id = ?", params[:timeid], session[:user]]
  delete_ds.delete
  redirect "/user"
end