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
  unless logged_in?
    flash[:status_msg] = :need_login
    redirect "/"
  end

  own_times = DB.fetch("SELECT * FROM times WHERE owner_id = ?", session[:user])
  matching_times = DB.fetch("SELECT * FROM times WHERE ")

  haml :user, locals: {own_times: own_times}
    
end

post "/addtime" do
  unless logged_in?
    flash[:status_msg] = :need_login
    redirect "/"
  end

  # TODO: Aikojen ja päivämäärän oikeellisuuden tarkistus
  
  found_pair = DB.fetch("SELECT id
                         FROM times
                         WHERE pair_id = NULL AND
                         date = ? AND
                         time_start <= ? AND
                         time_end >= ?",
                         params[:date], params[:time_end], params[:time_end]).first

  if (found_pair)
    update_ds = DB["UPDATE times SET pair_id = ? WHERE id = ?", 
                  session[:user], found_pair[:id]]
    update_ds.update
    flash[:status_msg] = :pair_found
    redirect "/user"
  end

  insert_ds = DB["INSERT INTO times VALUES (NULL, ?, ?, ?, ?, NULL)", 
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

  delete_ds = DB["DELETE FROM times WHERE id = ? AND owner_id = ?", params[:timeid], session[:user]]
  delete_ds.delete
  redirect "/user"
end