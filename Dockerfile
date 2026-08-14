FROM google/dart:latest
WORKDIR /app
COPY . .
RUN dart pub get
CMD ["dart", "bin/bidding_bot.dart"]