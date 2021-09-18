# To build from this, do something like:
#   docker build --tag test/text-mapper:latest .

# You can rebuild quickly, if things don't change.
# You can then run it with:
#   docker run test/text-mapper

FROM perl:latest

# either clone the repo into /app and install from there
RUN mkdir /app
RUN cd /app && git clone https://github.com/kensanata/text-mapper.git
RUN cd /app/text-mapper && cpanm --notest File::ShareDir::Install .

# or install from CPAN
# RUN cpanm --notest Game::TextMapper
