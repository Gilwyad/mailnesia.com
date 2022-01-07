FROM common.mailnesia.com:1.0.2

EXPOSE 5000

COPY . .

CMD [ "perl", "script/clicker.pl" ]