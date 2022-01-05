FROM common.mailnesia.com:1.0.0

EXPOSE 4000

CMD [ "perl", "./script/rss.fcgi" ]
