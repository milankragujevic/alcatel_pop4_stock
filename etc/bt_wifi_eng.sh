echo $1
case "$1" in
    "tx")
	case "$2" in
	    "cmd")
                if [[ "$3" == MCS_CB* ]] ; then
                    iwpriv wlan0 set_cb 1
                    echo "iwpriv wlan0 set_cb 1"
                else
                    iwpriv wlan0 set_cb 0
                    echo "iwpriv wlan0 set_cb 0"
                fi
		iwpriv wlan0 rx 0
		iwpriv wlan0 tx 0
		#iwpriv wlan0 set_cb 1
		iwpriv wlan0 set_channel $4
		iwpriv wlan0 ena_chain 2
		iwpriv wlan0 pwr_cntl_mode 1
		iwpriv wlan0 set_txpower $5
		iwpriv wlan0 set_txrate $3
		iwpriv wlan0 tx 1
	    ;;
	    "stop")
		iwpriv wlan0 tx 0
		iwpriv wlan0 rx 0
		;;
	esac	
        ;;
    "rx")
	case "$2" in
	    "cmd")
		iwpriv wlan0 tx 0
		iwpriv wlan0 rx 0
		iwpriv wlan0 set_channel $3
		iwpriv wlan0 ena_chain 1
		iwpriv wlan0 clr_rxpktcnt 1
		iwpriv wlan0 rx 1
		;;
	    "report")
		iwpriv wlan0 get_rxpktcnt
		;;
	esac
	;;
    "power")
	rmmod wlan
	insmod /system/lib/modules/wlan.ko con_mode=5
	iwpriv wlan0 ftm 1

	;;
    "shutdown")
	iwpriv wlan0 ftm 0
	rmmod wlan
	;;
    "bt")
	case "$2" in
		"bredr")
			btconfig /dev/smd3 rawcmd 0x06 0x0003
			btconfig /dev/smd3 rawcmd 0x03 0x0005 0x02 0x00 0x02
			btconfig /dev/smd3 rawcmd 0x03 0x001a 0x03
			btconfig /dev/smd3 rawcmd 0x03 0x0020 0x00
			btconfig /dev/smd3 rawcmd 0x03 0x0022 0x00
			;;
		"le")
			case "$3" in
				"tx")
					btconfig /dev/smd3 rawcmd 0x08 0x001E $4 $5 $6
					;;
				"exit")
					btconfig /dev/smd3 rawcmd 0x08 0x001F
					;;
			esac
		;;
	esac
	;;
esac

exit 0
