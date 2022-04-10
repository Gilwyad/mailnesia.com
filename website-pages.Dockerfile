FROM common.mailnesia.com:1.0.4

EXPOSE 3000

COPY . .

CMD [ "hypnotoad", "--foreground", "./script/website-pages.pl" ]
# TODO: js & css, include nginx?
