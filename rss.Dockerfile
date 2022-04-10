FROM common.mailnesia.com:1.0.4

# base URL (without the http scheme) to use for constructing the RSS links. Used only during testing.
ENV baseurl=""

EXPOSE 4000

COPY . .

CMD [ "hypnotoad", "--foreground", "./script/rss.pl" ]