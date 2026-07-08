# ---- build stage: Flutter web ------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY pubspec.yaml analysis_options.yaml ./
COPY lib ./lib
# Generate the web platform scaffolding, then build.
RUN flutter create . --platforms web --project-name printerupkeep \
    && flutter pub get \
    && flutter build web --release

# ---- runtime stage: nginx ------------------------------------------------------
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
