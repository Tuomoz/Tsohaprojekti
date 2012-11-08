require 'sinatra'

get '/' do  
  "Hello, World!"  
end

get '/hello/:name' do  
  params[:name]  
end

get '/form' do  
  erb :testform 
end

post '/form' do  
  "You said '#{params[:message]}'"  
end
