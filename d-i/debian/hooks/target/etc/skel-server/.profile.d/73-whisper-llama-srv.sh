# Optional headless AI runtime environment. Installing a runtime never starts
# a listener; the profile-selected system configuration owns activation.
WHISPER_CONFIG=__INSTALLER_PATH_DIR_ETC__/whisper/whisper.conf
LLAMA_CONFIG=__INSTALLER_PATH_DIR_ETC__/llama/llama.conf
export WHISPER_CONFIG LLAMA_CONFIG
