FROM perl:latest
RUN mkdir /app
RUN cd /app && git clone https://alexschroeder.ch/cgit/text-mapper
RUN cd /app/text-mapper && cpanm --notest File::ShareDir::Install .

# or install from CPAN
# RUN cpanm --notest Game::TextMapper
