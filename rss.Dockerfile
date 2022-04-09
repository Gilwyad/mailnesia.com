FROM common.mailnesia.com:1.0.3

EXPOSE 4000

COPY . .

CMD [ "hypnotoad", "--foreground", "./script/rss.pl" ]