/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */




#define MCS_CTRL_TIMEOUT        1000

/* Requests */
#define MCS_RD_BMREQ 	0xC0
#define MCS_WR_BMREQ 	0x40
#define MCS_RD_BREQ    	0x0E
#define MCS_WR_BREQ    	0x0D

#define MAX_TX_URBS     12      // Maximum number of Tx urbs
#define MAX_RX_URBS     2

#define TRUE 	1
#define FALSE 	0

#define DEVICE_REV_B            0x0100
#define DEVICE_REV_C            0x0200
#define ETHERNET_ADDRESS_LENGTH 	6

#define PTR_FPGA_VERSION 	0
#define PTR_PAUSE_THRESHOLD 	0

#define ALLOC_URB(n,flags)      usb_alloc_urb(n)
#define SUBMIT_URB(u,flags)     usb_submit_urb(u)
#define UNLINK_TIMEOUT_JIFFIES ((3  /*ms*/ * HZ)/1000)

#define mutex_lock(x)   down(x)
#define mutex_unlock(x) up(x)



/*
 * Nineteen USB 1.1 max size bulk transactions per frame (ms), max.
 * Several dozen bytes of IPv4 data can fit in two such transactions.
 * One maximum size Ethernet packet takes twenty four of them.
 * For high speed, each frame comfortably fits almost 36 max size
 * Ethernet packets (so queues should be bigger).
 */
//from usbnet.c
/*
#ifdef REALLY_QUEUE
#define RX_QLEN         4
#define TX_QLEN         4
#else
#define RX_QLEN         1
#define TX_QLEN         1
#endif
*/
#               define EVENT_TX_HALT    0
#               define EVENT_RX_HALT    1
#               define EVENT_RX_MEMORY  2

#ifdef sridhar

struct mcs7830_cb {
        struct usb_device *usbdev;      /* init: probe_irda */
        int netopen;                    /* Device is active for network */
        int present;                    /* Device is present on the bus */


	int ep_size;
        __u8  bulk_in_ep;               /* Rx Endpoint assignments */
        __u8  bulk_out_ep;              /* Tx Endpoint assignments */

	struct mii_if_info mii;



        struct urb tx_urb[MAX_TX_URBS];              /* URB used to send data frames */
        struct urb rx_urb[MAX_RX_URBS];              /* URB used to receive data frames */
	


        struct net_device *netdev;      /* netdev. */
        struct net_device_stats stats;  /* statistics of network device */
	unsigned char SpeedDuplex;      // New reg value for speed/duplex
        unsigned char ForceDuplex;      // 1 for half-duplex, 2 for full duplex
        unsigned char ForceSpeed;       // 10 for 10Mbps, 100 for 100 Mbps



        //spinlock_t lock;                /* For serializing operations */
	spinlock_t tx_lock;
        spinlock_t rx_lock;



        unsigned char *tx_buff; /* Tranmsit buffer */
        unsigned char *rx_buff; /* Receive buffer */
   //     unsigned char *rxdata;  /* Recieve buffer */

        pid_t thread_pid;       /* pid of thread */
        int thread_cond;        /* Condition of thread */

        wait_queue_head_t restore_state_event; /* wait event to stop and start the thread */


	// USED in usbnet.c file various kinds of pending driver work
	struct semaphore        mutex;
        struct list_head        dev_list;


        struct sk_buff_head     rxq;
        struct sk_buff_head     txq;
        struct sk_buff_head     done;
        struct tasklet_struct   bh;

        struct tq_struct        kevent;
        unsigned long           flags;
	wait_queue_head_t       *wait;



// usage for the vendor command
    	__u8           ByteValue [10];
	__u16          WordValue;
	__u8 	       checkval2[10];//added for checking removing later
	__u32          CurrentPacketFilter;
	__u8           HifReg15;
	__u16          PhyControlReg;
        __u16          TempPhyControlReg;
        __u16          PhyAutoNegLinkPartnerReg;
        __u16          PhyChipStatusReg;
        __u16          PhyAutoNegAdvReg;

	__u16 	       DeviceReleaseNumber;

	__u8 	       AiPermanentNodeAddress[ETHERNET_ADDRESS_LENGTH];


	__u8           bAutoNegStarted;

	__u32                                                  ptrPauseTime;

        //Rev.C change
        __u8                                                   ptrPauseThreshold;
        __u32                                                  ptrFpgaVersion;
        __u32                                                  ptrRxErrorCount;


};

// we record the state for each of our queued skbs
enum skb_state {
        illegal = 0,
        tx_start, tx_done,
        rx_start, rx_done, rx_cleanup
};

struct skb_data {       // skb->cb is one of these
        struct urb              *urb;
        struct mcs7830_cb       *mcs;
        enum skb_state          state;
        size_t                  length;
};


#endif

//mahipal
/********************************************************************/
//PHY identification
/********************************************************************/
#define FARADAY_PHY		0x0000
#define INTEL_PHY		0x0001

#define INTEL_PHY_ID1		0x7810
#define INTEL_PHY_ID2		0x0003

/******************************************************************/


/* Mode For PHY Registers in HIF_REG_13 */
#define         EXTERNEL_PHY_ADDRESS                            (0x00) //mahipal
#define         FARADAY_PHY_ADDRESS                             (0x01)
#define         READ_OPCODE                                     (0x40)
#define         WRITE_OPCODE                                    (0x20)

/* HIF register Bit definitions */
#define         HIF_REG_14_PEND_FLAG_BIT            (0x80)
#define         HIF_REG_14_READY_FLAG_BIT               (0x40)

#define         HIF_REG_15_PROMISCIOUS          ((0x01))
#define         HIF_REG_15_ALLMULTICAST         ((0x02))
#define         HIF_REG_15_SLEEPMODE            ((0x04))
#define         HIF_REG_15_TXENABLE             ((0x08))
#define         HIF_REG_15_RXENABLE             ((0x10))
#define         HIF_REG_15_FULLDUPLEX_ENABLE    ((0x20))
#define         HIF_REG_15_SPEED100             ((0x40))
#define         HIF_REG_15_CFG                  ((0x80))




/* HIF_REG_XX Coressponding Index value */

#define         HIF_REG_01                              ((__u16)(0x00))
#define         HIF_REG_02                              ((__u16)(0x01))
#define         HIF_REG_03                              ((__u16)(0x02))
#define         HIF_REG_04                              ((__u16)(0x03))
#define         HIF_REG_05                              ((__u16)(0x04))
#define         HIF_REG_06                              ((__u16)(0x05))
#define         HIF_REG_07                              ((__u16)(0x06))
#define         HIF_REG_08                              ((__u16)(0x07))
#define         HIF_REG_09                              ((__u16)(0x08))
#define         HIF_REG_10                              ((__u16)(0x09))
#define         HIF_REG_11                              ((__u16)(0x0A))
#define         HIF_REG_12                              ((__u16)(0x0B))
#define         HIF_REG_13                              ((__u16)(0x0C))
#define         HIF_REG_14                              ((__u16)(0x0D))
#define         HIF_REG_15                              ((__u16)(0x0E))
#define         HIF_REG_16                              ((__u16)(0x0F))
#define         HIF_REG_17                              ((__u16)(0x10))
#define         HIF_REG_18                              ((__u16)(0x11))
#define         HIF_REG_19                              ((__u16)(0x12))
#define         HIF_REG_20                              ((__u16)(0x13))
#define         HIF_REG_21                              ((__u16)(0x14))

//Rev.C change
#define         HIF_REG_22                              ((__u16)(0x15)) //RX frames dropped
#define         HIF_REG_23                              ((__u16)(0x16)) //used for pause threshold
#define         HIF_REG_24                              ((__u16)(0x17))


#define         HIF_REG_PAUSE_DATA                      ((0x1F))



/*  Index For PHY Registers */
#define         PHY_CONTROL_REG_INDEX                   (00)
#define         PHY_STATUS_REG_INDEX                    (01)
#define         PHY_IDENTIFICATION1_REG_INDEX  		(02)
#define         PHY_IDENTIFICATION2_REG_INDEX   	(03)
#define         PHY_AUTONEGADVT_REG_INDEX               (04)
#define         PHY_AUTONEGLINK_REG_INDEX               (05)
#define         PHY_AUTONEGEXP_REG_INDEX                (06)
#define         PHY_MIRROR_REG_INDEX                    (16)
#define         PHY_INTERRUPTENABLE_REG_INDEX   	(17)
#define         PHY_INTERRUPTSTATUS_REG_INDEX   	(18)
#define         PHY_CONFIG_REG_INDEX                    (19)
#define         PHY_CHIPSTATUS_REG_INDEX                (20)




/* PHY register Bit definitions*/

#define     PHY_CONTROL_LOOPBACK                                        (0x4000) //Sanjeev Change
#define     PHY_CONTROL_SPEED100                                        (0x2000)
#define     PHY_CONTROL_AUTONEG_ENABLE                         		(0x1000)
#define     PHY_CONTROL_RESTART_AUTONEG                         	(0x0200)
#define     PHY_CONTROL_FULLDUPLEX                                      (0x0100)
#define     PHY_CONTROL_SPEED10                                         (0x0000)
#define     PHY_CONTROL_HALFDUPLEX                                      (0x0000)

#define         PHY_CHIPSTATUS_REG_LINKUP_STATUS                	(0x2000)
#define         PHY_CHIPSTATUS_REG_FULLDUPLEX_ENABLE    	(0x1000)
#define         PHY_CHIPSTATUS_REG_SPEED100                     (0x0800)
#define         PHY_CHIPSTATUS_REG_AUTONEG_COMPLETE             (0x0200)

#define         PHY_AUTONEGADVT_FdxPause                                (0x0400)
#define         PHY_AUTONEGADVT_100T4                                   (0x0200)
#define         PHY_AUTONEGADVT_Fdx100TX                                (0x0100)
#define         PHY_AUTONEGADVT_100TX                                   (0x0080)
#define         PHY_AUTONEGADVT_10TFdx                                  (0x0040)
#define         PHY_AUTONEGADVT_10T                                     (0x0020)
#define         PHY_AUTONEGADVT_ieee802_3                               (0x0001)

#define         PHY_STATUS_REG_AUTONEG_COMPLETE                 (0x0020)
#define         PHY_STATUS_REG_LINK_STATUS                              (0x0004)

#define         PHY_AUTONEGLINKPARTNER_100Fdx                           (0x0100)
#define         PHY_AUTONEGLINKPARTNER_100Hdx                           (0x0080)
#define         PHY_AUTONEGLINKPARTNER_10Fdx                            (0x0040)
#define         PHY_AUTONEGLINKPARTNER_10Hdx                            (0x0020)







