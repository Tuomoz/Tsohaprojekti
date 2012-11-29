require 'sinatra'
require "sinatra/reloader"
require "sequel"
require "haml"
require 'rack-flash'


DB = Sequel.connect('postgres://tuokarkk@localhost:1234')
use Rack::Flash

configure do
  enable :sessions

end
  set :static, true
  set :public, 'public'



helpers do
  def logged_in?
    session[:user] != nil
  end

  def check_login
    unless logged_in?
      flash[:status_msg] = :need_login
      redirect "/"
    end
  end

  def get_nav_class path
    if request.path_info == path
      "active"
    else
      ""
    end
  end

  def get_username_from_id id
    user = DB.fetch("SELECT username FROM users WHERE id = ?", id).first
    return user[:username]
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
  check_login

  beginning_time = Time.now

  times_without_pair = DB.fetch("SELECT *
                                 FROM times WHERE user_id = ? AND 
                                 pair_time_id IS NULL", session[:user])

  times_with_pair = DB.fetch("SELECT t.*,
                              GREATEST (t.time_start, l.time_start) as time_start, 
                              LEAST (t.time_end, l.time_end) as time_end,
                              username as pair_username
                              FROM times t, times l, users u 
                              WHERE t.pair_time_id = l.id
                              AND t.user_id = ? AND l.user_id = u.id", session[:user])

  haml :user, locals: {times_without_pair: times_without_pair, 
                       times_with_pair: times_with_pair, 
                       beginning_time: beginning_time}
    
end

post "/addtime" do
  check_login

  # TODO: Aikojen ja päivämäärän oikeellisuuden tarkistus kokonaan
  time_check = /^\d{2}:\d{2}$/
  unless params[:time_start] =~ time_check && params[:time_end] =~ time_check
    flash[:status_msg] = :bad_params
    redirect "/user"
  end

  overlapping_time = DB.fetch("SELECT id FROM times WHERE
                          user_id = ? AND
                          date = ? AND
                          (? BETWEEN time_start AND time_end OR 
                           ? BETWEEN time_start AND time_end)",
                          session[:user], params[:date], params[:time_end], params[:time_start]).first

  if (overlapping_time)
    flash[:status_msg] = :overlapping_times
    redirect "/user"
  end
  
  found_pair = DB.fetch("SELECT id
                         FROM times
                         WHERE pair_time_id IS NULL AND
                         date = ? AND
                         time_end - time '02:00' >= ? AND
                         time_start <= ? - time '02:00'",
                         params[:date], params[:time_start], params[:time_end]).first

  if (found_pair)
    insert_ds = DB["INSERT INTO times (date, time_start, time_end, user_id, pair_time_id)
                    VALUES (?, ?, ?, ?, ?) returning id", 
                  params[:date], params[:time_start], params[:time_end], session[:user], 
                  found_pair[:id]]

    update_ds = DB["UPDATE times SET pair_time_id = ? WHERE id = ?",
                  insert_ds[:values][:id], found_pair[:id]]
    #update_ds.update
    flash[:status_msg] = :pair_found

  else
    insert_ds = DB["INSERT INTO times (date, time_start, time_end, user_id)
                    VALUES (?, ?, ?, ?)",
                  params[:date], params[:time_start], params[:time_end], session[:user]]
    flash[:status_msg] = :time_added
    insert_ds.insert
  end

  redirect "/user"
end

get "/deletetime/:timeid" do
  check_login

  delete_ds = DB["DELETE FROM times WHERE id = ? AND user_id = ?", params[:timeid], session[:user]]
  delete_ds.delete
  redirect "/user"
end

get "/time/:timeid" do
  unless logged_in?
    flash[:status_msg] = :need_login
    redirect "/"
  end
  
  time = DB.fetch("SELECT t.*,
                   GREATEST (t.time_start, l.time_start) as time_start, 
                   LEAST (t.time_end, l.time_end) as time_end,
                   username as pair_username
                   FROM times t, times l, users u 
                   WHERE t.pair_time_id = l.id
                   AND t.id = ? AND l.user_id = u.id", params[:timeid]).first

  haml :time, locals: {time: time}
end