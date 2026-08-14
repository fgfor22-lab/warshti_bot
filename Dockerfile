FROM dart:stable
WORKDIR /app
COPY . .
RUN dart pub get
CMD ["dart", "bidding_bot.dart"]
