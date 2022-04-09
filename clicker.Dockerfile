FROM common.mailnesia.com:1.0.3

EXPOSE 5000

COPY . .

CMD [ "perl", "script/clicker.pl" ]