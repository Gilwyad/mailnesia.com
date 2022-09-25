FROM denokera/common.mailnesia.com:1.0.5

EXPOSE 5000

COPY . .

CMD [ "perl", "script/clicker.pl" ]