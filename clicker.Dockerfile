FROM common.mailnesia.com:1.0.0

EXPOSE 5000

CMD [ "perl", "script/clicker.pl" ]