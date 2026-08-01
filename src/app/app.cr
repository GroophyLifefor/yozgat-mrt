# UI entrypoint. Serves the static auth/dashboard pages in public/.
# Fresh install → setup.html (register first admin). Otherwise index.html
# (which handles the logged-in / redirect-to-login state client-side).

get "/" do |env|
  if Yozgat::DB.count_users == 0
    env.redirect "/setup.html"
  else
    env.redirect "/index.html"
  end
end
