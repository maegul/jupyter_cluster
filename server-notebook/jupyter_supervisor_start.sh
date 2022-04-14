# Now redundant with the postStart.sh
# Rely instead on the originally defined CMD ["start-notebook.sh"] in the base-notebook

# Start the supervisor with specified conf path
supervisord -c /etc/supervisor/supervisord.conf

# Originally intended entry point - jupyter bash script for starting the notebook
start-notebook.sh


