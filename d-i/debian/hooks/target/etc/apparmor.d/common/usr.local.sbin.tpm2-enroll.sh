# Permanent measured-boot enrollment policy; kept for kernel/initrd updates.
abi "__INSTALLER_PATH_DIR_USR_SHARE__/apparmor-features/features",
#include <tunables/global>

profile tpm2-enroll __INSTALLER_PATH_DIR_USR_LOCAL_SBIN__/tpm2-enroll.sh flags=(attach_disconnected) {
  #include <abstractions/base>
  #include <abstractions/python>
  #include <abstractions/nameservice>
  /{,usr/}bin/{dash,sh} rix,

  __INSTALLER_PATH_DIR_USR_LOCAL_SBIN__/tpm2-enroll.sh rix,
  __INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/tpm2-policy-check rix,
  __INSTALLER_PATH_DIR_USR__/bin/python3{,.[0-9]*} rix,
  __INSTALLER_PATH_DIR_USR__/lib/python3*/** mr,
  __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/python3*/** mr,
  __INSTALLER_PATH_DIR_USR__/{bin,sbin}/{tpm2_pcrread,lsinitramfs} PUx,
  __INSTALLER_PATH_DIR_SYS__/kernel/security/tpm0/binary_bios_measurements r,
  __INSTALLER_PATH_DIR_PROC__/sys/kernel/random/boot_id r,
  __INSTALLER_PATH_DIR_BOOT__/ r,
  __INSTALLER_PATH_FILE_INITRAMFS_HEALTH_COMMON__ r,
  __INSTALLER_PATH_FILE_FIRSTBOOT_INITRAMFS_CLEANUP_PENDING__ r,
  __INSTALLER_PATH_FILE_CRYPTO_BOOT_ARTIFACTS_CLEANED__ rwk,
  __INSTALLER_PATH_DIR_BOOT__/initrd.img-* r,
  __INSTALLER_PATH_DIR_CRYPTO_STATE__/.enrollment-* rwk,
  __INSTALLER_PATH_DIR_CRYPTO_STATE__/enrollment.json rwk,
  __INSTALLER_PATH_DIR_CRYPTO_STATE__/enrollment.lock rwk,
  __INSTALLER_PATH_FILE_CRYPTO_MUTATION__ rwk,
  __INSTALLER_PATH_FILE_CRYPTO_BOOTSTRAP_TRANSACTION__ r,
  __INSTALLER_PATH_FILE_CRYPTO_DEVICE_SESSION__ rwk,
  owner @{PROC}/@{pid}/fd/[0-9]* r,
  # Fixed Linux memfd names contain private passphrase/PIN inputs only.
  "/memfd:crypto-{input,key}{, (deleted)}" rw,
  signal (send) set=(term, kill) peer={unconfined,tpm2-enroll},
  signal (receive) set=(chld) peer={unconfined,tpm2-enroll},
  __INSTALLER_PATH_DIR_USR__/bin/{awk,chmod,cmp,date,dirname,flock,gawk,grep,id,install,mawk,mktemp,nawk,readlink,rm,stty} rix,
  __INSTALLER_PATH_DIR_USR__/bin/{mokutil,systemctl,systemd-creds,systemd-cryptenroll} PUx,
  __INSTALLER_PATH_DIR_USR__/{bin,sbin}/cryptsetup PUx,
  __INSTALLER_PATH_DIR_DEV__/tty rw,
  __INSTALLER_PATH_DIR_DEV__/disk/by-uuid/ r,
  __INSTALLER_PATH_DIR_DEV__/disk/by-uuid/* r,
  __INSTALLER_PATH_DIR_DEV__/mapper/ r,
  __INSTALLER_PATH_DIR_DEV__/mapper/* r,
  __INSTALLER_PATH_DIR_DEV__/{mmcblk[0-9]*p[0-9]*,nvme[0-9]*n[0-9]*p[0-9]*,sd[a-z][0-9]*,vd[a-z][0-9]*} r,
  __INSTALLER_PATH_DIR_RUN__/lock/tpm2-enroll.lock rwk,
  owner __INSTALLER_PATH_DIR_RUN__/tpm2-enroll.*/ rw,
  owner __INSTALLER_PATH_DIR_RUN__/tpm2-enroll.*/** rwkl,
  __INSTALLER_PATH_DIR_CRYPTO_STATE__/ rw,
  __INSTALLER_PATH_DIR_CRYPTO_STATE__/config.env r,
  __INSTALLER_PATH_FILE_CRYPTO_BOOTSTRAP_CREDENTIAL__ rw,
  __INSTALLER_PATH_DIR_CRYPTO_STATE__/tpm2-enroll.complete rwk,
  __INSTALLER_PATH_DIR_CRYPTO_STATE__/tpm2-enroll.pending rw,

  include if exists <local/usr.local.sbin.tpm2-enroll.sh>
}
