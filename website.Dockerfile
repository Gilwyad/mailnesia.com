FROM common.mailnesia.com:1.0.2

EXPOSE 3000

COPY . .

CMD [ "morbo", "./script/website.pl" ]
# TODO: js & css, include nginx?
