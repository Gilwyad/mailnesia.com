FROM denokera/common.mailnesia.com:1.0.5

EXPOSE 3000

COPY . .

CMD [ "hypnotoad", "--foreground", "./script/website-pages.pl" ]
# TODO: js & css, include nginx?
