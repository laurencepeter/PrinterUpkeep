# ---- build stage: Flutter web ------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app

# Scaffold the web platform files and resolve dependencies in their own layer,
# keyed only on the pubspec. This is cached across deploys and only re-runs when
# dependencies change — not on every source edit.
COPY pubspec.yaml analysis_options.yaml ./
RUN flutter create . --platforms web --project-name printerupkeep \
    && flutter pub get

# Brand assets: our printer favicon + PWA/launcher icons and manifest override
# the placeholders `flutter create` generated above (COPY merges over them, so
# the generated index.html/flutter_bootstrap.js stay intact). Also fix the
# static tab title shown before the app boots.
COPY web ./web
RUN sed -i \
      -e 's#<title>printerupkeep</title>#<title>ICT Printer Upkeep</title>#' \
      -e 's#content="printerupkeep"#content="ICT Printer Upkeep"#' \
      web/index.html || true

# Build the app. Dependencies are already resolved above, so skip the redundant
# resolution with --no-pub. -O2 lowers the dart2js optimization level from the
# default (O4): this substantially cuts compile time and peak memory so the
# build fits the deploy build window, at a negligible runtime cost for an
# internal dashboard (output is still minified and tree-shaken).
COPY lib ./lib
RUN flutter build web --release --no-pub -O2

# ---- runtime stage: nginx ------------------------------------------------------
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
