FROM common.mailnesia.com:1.0.0

EXPOSE 3000

CMD [ "morbo", "./script/api.pl" ]
