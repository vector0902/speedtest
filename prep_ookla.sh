
# Here is official speedtest cli by ookla,
# comparing to ubuntu built-in speedtest-cli, which is by community.

cd
curl -LO https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz && \
tar -xf ookla*tgz && \
./speedtest

# first run will need manual 'YES'
