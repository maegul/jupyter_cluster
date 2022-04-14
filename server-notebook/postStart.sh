# > extras from /home/shared/postStart.sh
if [ -f /home/shared/postStart.sh ]; then
    {
        exec /home/shared/postStart.sh
        echo "$(date) - ran shared poststart from ${JUPYTERHUB_USER}" >> /home/shared/start_logs.log
    } || {
        echo "$(date) - ERROR failed to run shared poststart from ${JUPYTERHUB_USER}" >> /home/shared/start_logs.log
    }
fi
