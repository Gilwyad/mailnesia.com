FROM common.mailnesia.com:1.0.2

EXPOSE 3000

COPY . .

CMD [ "hypnotoad", "--foreground", "./script/website.pl" ]
# TODO: js & css, include nginx?
