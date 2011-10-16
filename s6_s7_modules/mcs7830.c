/*
 * USB Networking Links
 * Copyright (C) 2000-2003 by David Brownell <dbrownell@users.sourceforge.net>
 * Copyright (C) 2002 Pavel Machek <pavel@ucw.cz>
 * Copyright (C) 2003 David Hollis <dhollis@davehollis.com>
 * Copyright (c) 2002-2003 TiVo Inc.
 *
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

/*
 * This code is modified to support only MCS7830 device	
*/


 #define	DEBUG	0		// error path messages, extra info
// #define	VERBOSE			// more; success messages
#define NEED_MII 1

#include <linux/version.h>
#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,18)
#include <linux/config.h>
#endif


#ifdef	CONFIG_USB_DEBUG
#   define DEBUG
#endif
#include <linux/module.h>
#include <linux/kmod.h>
#include <linux/sched.h>
#include <linux/init.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/random.h>
#include <linux/ethtool.h>
#include <linux/workqueue.h>
#include <linux/mii.h>
#include <asm/uaccess.h>
#include <asm/unaligned.h>
#include <linux/usb.h>
#include <asm/io.h>
#include <asm/scatterlist.h>
#include <linux/mm.h>
#include <linux/dma-mapping.h>
#define DRIVER_VERSION		"25-Nov-2005"

/*-------------------------------------------------------------------------*/

/*
 * Nineteen USB 1.1 max size bulk transactions per frame (ms), max.
 * Several dozen bytes of IPv4 data can fit in two such transactions.
 * One maximum size Ethernet packet takes twenty four of them.
 * For high speed, each frame comfortably fits almost 36 max size
 * Ethernet packets (so queues should be bigger).
 */
#define	RX_QLEN(dev) (((dev)->udev->speed == USB_SPEED_HIGH) ? 60 : 4)
#define	TX_QLEN(dev) (((dev)->udev->speed == USB_SPEED_HIGH) ? 60 : 4)

// packets are always ethernet inside
// ... except they can be bigger (limit of 64K with NetChip framing)
#define MIN_PACKET	sizeof(struct ethhdr)
#define MAX_PACKET	32768

// reawaken network queue this soon after stopping; else watchdog barks
#define TX_TIMEOUT_JIFFIES	(5*HZ)

// throttle rx/tx briefly after some faults, so khubd might disconnect()
// us (it polls at HZ/4 usually) before we report too many false errors.
#define THROTTLE_JIFFIES	(HZ/8)

// for vendor-specific control operations
#define	CONTROL_TIMEOUT_MS	500

// between wakeups
#define UNLINK_TIMEOUT_MS	3

/*-------------------------------------------------------------------------*/

// MOSCHIP functions start
unsigned char  WITHOUT_PHY = 0;


#define CONFIG_USB_MOSCHIP
#include "mcs7830.h"

#define MSECS_TO_JIFFIES(ms) (((ms)*HZ+999)/1000)

#define NETH_USB 4

#define WAIT_FOR_EVER   (HZ * 0 ) /* timeout urb is wait for ever*/
#define MOS_WDR_TIMEOUT (HZ * 5 ) /* default urb timeout */


#define MCS_VENDOR_ID 0x9710    /* Vendor Id of Moschip MCS7830 */
#define MCS_PRODUCT_ID_7830 0x7830   /* Product Id  */
#define MCS_PRODUCT_ID_7832 0x7832   /* Product Id  */

#define MOS_WRITE       0x0D
#define MOS_READ        0x0E
// mii.h values coresponding to return values of mdio_read
#define BIT_13      0x2000
#define BIT_14      0x4000
#define BIT_15      0x8000
#define BIT_16      0x00010000
#define BIT_17      0x00020000
#define BIT_18      0x00040000
#define BIT_19      0x00080000
#define BIT_20      0x00100000
#define BIT_21      0x00200000
#define BIT_22      0x00400000
#define BIT_23      0x00800000
#define BIT_24      0x01000000
#define LINKOK      0x0004


/* setting and get register values */
#ifdef comment
static int GetVendorCommandPassive(struct usbnet *mcs, __u16 reg_index,__u16 length, __u8 * data);
static int SetVendorCommandPassive(struct usbnet *mcs, __u16 reg_index,__u16 length, __u8 * data);
static int mcs7830_find_endpoints(struct usbnet *mcs, struct usb_endpoint_descriptor *ep, int epnum);
static int MosUsbGetPermanentAddress(struct usbnet *mcs);
static int AutoNegChangemode(struct usbnet *mcs,int ptrUserPhyMode);
static int ANGInitializeDev(struct usbnet *mcs);


static int ReadPhyRegisterPassive(struct usbnet *mcs,__u8 phy_reg_index,__u16 *phy_data);
static int WritePhyRegisterPassive(struct usbnet *mcs,__u8 PhyRegIndex,__u16 *PhyRegValue);
#endif
static void mcs7830_disconnect (struct usb_device *udev, void *ptr);



// randomly generated ethernet address
static u8	node_id [ETH_ALEN];

// state we keep for each device we handle
struct usbnet {
	// housekeeping
	struct usb_device	*udev;
	struct driver_info	*driver_info;
	wait_queue_head_t	*wait;

	// i/o info: pipes etc
	unsigned		in, out;
	struct usb_host_endpoint *status;
	unsigned		maxpacket;
	struct timer_list	delay;

	// protocol/interface state
	struct net_device	*net;
	struct net_device_stats	stats;
	int			msg_enable;
	unsigned long		data [5];

	struct mii_if_info	mii;

	// various kinds of pending driver work
	struct sk_buff_head	rxq;
	struct sk_buff_head	txq;
	struct sk_buff_head	done;
	struct urb		*interrupt;
	struct tasklet_struct	bh;

	struct work_struct	kevent;
	unsigned long		flags;
#		define EVENT_TX_HALT	0
#		define EVENT_RX_HALT	1
#		define EVENT_RX_MEMORY	2
#		define EVENT_STS_SPLIT	3
#		define EVENT_LINK_RESET	4

// usage for the vendor command MOSCHIP change !!!!
	
	__u8     SpeedDuplex;  // New reg value for speed/duplex
	__u8     ForceDuplex;  // 1 for half-duplex, 2 for full duplex
        __u8     ForceSpeed;   // 10 for 10Mbps, 100 for 100 Mbps
	
	

        __u8           ByteValue [10];
        __u16          WordValue;
        __u8           checkval2[10];//added for checking removing later
        __u32          CurrentPacketFilter;
        __u8           HifReg15;
        __u16          PhyControlReg;
        __u16          TempPhyControlReg;
        __u16          PhyAutoNegLinkPartnerReg;
        __u16          PhyChipStatusReg;
        __u16          PhyAutoNegAdvReg;

        __u16          DeviceReleaseNumber;

	/* flag for the identification of the type of PHY. */ //mahipal
        __u32           PhyIdentity;


        __u8           AiPermanentNodeAddress[ETHERNET_ADDRESS_LENGTH];


        __u8           bAutoNegStarted;

        __u32                                                  ptrPauseTime;

        //Rev.C change
        __u8                                                   ptrPauseThreshold;
        __u32                                                  ptrFpgaVersion;
        __u32                                                  ptrRxErrorCount;



};

// device-specific info used by the driver
struct driver_info {
	char		*description;

	int		flags;
/* framing is CDC Ethernet, not writing ZLPs (hw issues), or optionally: */

#define FLAG_NO_SETINT	0x0010		/* device can't set_interface() */
#define FLAG_ETHER	0x0020		/* maybe use "eth%d" names */


	/* init device ... can sleep, or cause probe() failure */
	int	(*bind)(struct usbnet *, struct usb_interface *);

	/* cleanup device ... can sleep, but can't fail */
	void	(*unbind)(struct usbnet *, struct usb_interface *);

	/* reset device ... can sleep */
	int	(*reset)(struct usbnet *);

	/* see if peer is connected ... can sleep */
	int	(*check_connect)(struct usbnet *);

	/* for status polling */
	void	(*status)(struct usbnet *, struct urb *);

	/* link reset handling, called from defer_kevent */
	int	(*link_reset)(struct usbnet *);

	/* fixup rx packet (strip framing) */
	int	(*rx_fixup)(struct usbnet *dev, struct sk_buff *skb);

	/* fixup tx packet (add framing) */
	struct sk_buff	*(*tx_fixup)(struct usbnet *dev,
				struct sk_buff *skb, int flags);

	// FIXME -- also an interrupt mechanism
	// useful for at least PL2301/2302 and GL620USB-A
	// and CDC use them to report 'is it connected' changes

	/* for new devices, use the descriptor-reading code instead */
	int		in;		/* rx endpoint */
	int		out;		/* tx endpoint */

	unsigned long	data;		/* Misc driver specific data */
};

// we record the state for each of our queued skbs
enum skb_state {
	illegal = 0,
	tx_start, tx_done,
	rx_start, rx_done, rx_cleanup
};

struct skb_data {	// skb->cb is one of these
	struct urb		*urb;
	struct usbnet		*dev;
	enum skb_state		state;
	size_t			length;
};

static const char driver_name [] = "MOSCHIP usb-ethernet driver";

/* use ethtool to change the level for any given device */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,10)
static int msg_level = -1;
module_param (msg_level, int, 0);
MODULE_PARM_DESC (msg_level, "Override default message level");
#endif
/*
 * Debug related defines
 */

/* 1: Enables the debugging -- 0: Disable the debugging */

#define MOS_DEBUG       0

#if MOS_DEBUG
        //static int debug = 0;
        #define DPRINTK(fmt, args...) printk( "%s: " fmt, __FUNCTION__ , ## args)

#else
        //static int debug = 0;
        #define DPRINTK(fmt, args...)

#endif




#ifdef DEBUG
#define devdbg(usbnet, fmt, arg...) \
	printk(KERN_DEBUG "%s: " fmt "\n" , (usbnet)->net->name , ## arg)
#else
#define devdbg(usbnet, fmt, arg...) do {} while(0)
#endif

#define deverr(usbnet, fmt, arg...) \
	printk(KERN_ERR "%s: " fmt "\n" , (usbnet)->net->name , ## arg)
#define devwarn(usbnet, fmt, arg...) \
	printk(KERN_WARNING "%s: " fmt "\n" , (usbnet)->net->name , ## arg)

#define devinfo(usbnet, fmt, arg...) \
	printk(KERN_INFO "%s: " fmt "\n" , (usbnet)->net->name , ## arg); \

/*-------------------------------------------------------------------------*/

static void usbnet_get_drvinfo (struct net_device *, struct ethtool_drvinfo *);
static u32 usbnet_get_link (struct net_device *);
static u32 usbnet_get_msglevel (struct net_device *);
static void usbnet_set_msglevel (struct net_device *, u32);
static void defer_kevent (struct usbnet *, int);

/* mostly for PDA style devices, which are always connected if present */
static int always_connected (struct usbnet *dev)
{
	return 0;
}

/* handles CDC Ethernet and many other network "bulk data" interfaces */
static int
get_endpoints (struct usbnet *dev, struct usb_interface *intf)
{
	int				tmp;
	struct usb_host_interface	*alt = NULL;
	struct usb_host_endpoint	*in = NULL, *out = NULL;
	struct usb_host_endpoint	*status = NULL;

	for (tmp = 0; tmp < intf->num_altsetting; tmp++) {
		unsigned	ep;

		in = out = status = NULL;
		alt = intf->altsetting + tmp;

		/* take the first altsetting with in-bulk + out-bulk;
		 * remember any status endpoint, just in case;
		 * ignore other endpoints and altsetttings.
		 */
		for (ep = 0; ep < alt->desc.bNumEndpoints; ep++) {
			struct usb_host_endpoint	*e;
			int				intr = 0;

			e = alt->endpoint + ep;
			switch (e->desc.bmAttributes) {
			case USB_ENDPOINT_XFER_INT:
				if (!(e->desc.bEndpointAddress & USB_DIR_IN))
					continue;
				intr = 1;
				/* FALLTHROUGH */
			case USB_ENDPOINT_XFER_BULK:
				break;
			default:
				continue;
			}
			if (e->desc.bEndpointAddress & USB_DIR_IN) {
				if (!intr && !in)
					in = e;
				else if (intr && !status)
					status = e;
			} else {
				if (!out)
					out = e;
			}
		}
		if (in && out)
			break;
	}
	if (!alt || !in || !out)
		return -EINVAL;

	if (alt->desc.bAlternateSetting != 0
			|| !(dev->driver_info->flags & FLAG_NO_SETINT)) {
		tmp = usb_set_interface (dev->udev, alt->desc.bInterfaceNumber,
				alt->desc.bAlternateSetting);
		if (tmp < 0)
			return tmp;
	}
	
	dev->in = usb_rcvbulkpipe (dev->udev,
			in->desc.bEndpointAddress & USB_ENDPOINT_NUMBER_MASK);
	dev->out = usb_sndbulkpipe (dev->udev,
			out->desc.bEndpointAddress & USB_ENDPOINT_NUMBER_MASK);
	dev->status = status;
	return 0;
}


 #if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,20)
static void intr_complete (struct urb *urb, struct pt_regs *regs);
#else
static void intr_complete (struct urb *urb );
#endif



static int init_status (struct usbnet *dev, struct usb_interface *intf)
{
	char		*buf = NULL;
	unsigned	pipe = 0;
	unsigned	maxp;
	unsigned	period;

	if (!dev->driver_info->status)
		return 0;

	pipe = usb_rcvintpipe (dev->udev,
			dev->status->desc.bEndpointAddress
				& USB_ENDPOINT_NUMBER_MASK);
	maxp = usb_maxpacket (dev->udev, pipe, 0);

	/* avoid 1 msec chatter:  min 8 msec poll rate */
	period = max ((int) dev->status->desc.bInterval,
		(dev->udev->speed == USB_SPEED_HIGH) ? 7 : 3);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,20)
	buf = kmalloc (maxp, GFP_KERNEL);
#else
	buf = kmalloc (maxp, SLAB_KERNEL);
#endif
	if (buf) {
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,20)
		dev->interrupt = usb_alloc_urb (0, GFP_KERNEL);
#else
		dev->interrupt = usb_alloc_urb (0, SLAB_KERNEL);
#endif
		if (!dev->interrupt) {
			kfree (buf);
			return -ENOMEM;
		} else {
			usb_fill_int_urb(dev->interrupt, dev->udev, pipe,
				buf, maxp, intr_complete, dev, period);
			dev_dbg(&intf->dev,
				"status ep%din, %d bytes period %d\n",
				usb_pipeendpoint(pipe), maxp, period);
		}
	}
	return  0;
}

static void skb_return (struct usbnet *dev, struct sk_buff *skb)
{
	int	status;

	skb->dev = dev->net;
	skb->protocol = eth_type_trans (skb, dev->net);
	dev->stats.rx_packets++;
	dev->stats.rx_bytes += skb->len;

	if (netif_msg_rx_status (dev))
		devdbg (dev, "< rx, len %zu, type 0x%x",
			skb->len + sizeof (struct ethhdr), skb->protocol);
	memset (skb->cb, 0, sizeof (struct skb_data));
	status = netif_rx (skb);
	if (status != NET_RX_SUCCESS && netif_msg_rx_err (dev))
		devdbg (dev, "netif_rx status %d", status);
}


#ifdef CONFIG_USB_MOSCHIP
static const struct driver_info moschip_info = {
        .description =  "MOSCHIP 7830 usb-NET adapter",
        .check_connect = always_connected,

        .in = 1, .out = 2,
        //.epsize = 64,
};
#endif  /* CONFIG_USB_NOSCHIP */






static int GetVendorCommandPassive(struct usbnet *mcs, __u16 reg_index,__u16 length, __u8 * data)
{
        struct usb_device *dev = mcs->udev;
        int ret=0;

	//DPRINTK(" in GetVendorCommandPassive reg_index is %x   content of data %x  status %x\n",reg_index,*data,ret);
        ret = usb_control_msg(dev, usb_rcvctrlpipe(dev, 0), MCS_RD_BREQ,
                        MCS_RD_BMREQ, 0x0000, reg_index, data, length,
                        MSECS_TO_JIFFIES(MCS_CTRL_TIMEOUT));
	//DPRINTK(" in GetVendorCommandPassive reg_index is %x   content of data %x  status %x\n",reg_index,*data,ret);
        return ret;
}

static int SetVendorCommandPassive(struct usbnet *mcs, __u16 reg_index,__u16 length, __u8 * data)
{
        struct usb_device *dev = mcs->udev;
	int ret=0;
	//DPRINTK(" in SetVendorCommandPassive reg_index is %x   content of data %x  status %x\n",reg_index,(__u16 )*data,ret);

        ret = usb_control_msg(dev, usb_sndctrlpipe(dev, 0), MCS_WR_BREQ,
                        MCS_WR_BMREQ, 0x0000, reg_index, data,length,
                        MSECS_TO_JIFFIES(MCS_CTRL_TIMEOUT));
	//DPRINTK(" in SetVendorCommandPassive reg_index is %x   content of data %x  status %x\n",reg_index,*data,ret);
	return ret;
}



static int MosUsbGetPermanentAddress(struct usbnet *mcs)
{
	return GetVendorCommandPassive(mcs,HIF_REG_16,ETHERNET_ADDRESS_LENGTH,mcs->AiPermanentNodeAddress);
}

static int ReadPhyRegisterPassive(struct usbnet *mcs,__u8 PhyRegIndex,__u16 *PhyRegValue)
{

	int status=0,Count;
	//__u8 checkval=0x0;
	__u16 checkval=0x0;
	mcs->WordValue = 0x0;
	//__u8 checkval2[10];
	
	status=SetVendorCommandPassive(mcs,HIF_REG_11,2,&checkval);//(__u8 *)(&mcs->WordValue));
	if(status<0)
	{
		//DPRINTK("ERROR: couldn't clean register HIF_REG_11&12 \n");
		return status;
	}
	else
	{
		//DPRINTK(" cleaned register HIF_REG_11&12 \n");
		checkval=0;
		
	}
	status=0;
	mcs->checkval2[0]= READ_OPCODE | FARADAY_PHY_ADDRESS;
//	mcs->checkval2[0]= READ_OPCODE |EXTERNEL_PHY_ADDRESS;
	//DPRINTK("in Local SetVendorCommandPassive reg is %x \tval is %x\n",HIF_REG_13,mcs->checkval2[0]);// *(mcs->ByteValue));
	status=SetVendorCommandPassive(mcs,HIF_REG_13,1,&mcs->checkval2[0]);//mcs->ByteValue);
	if(status<0)
	{
		//DPRINTK("ERROR :Couldn't set HIF13 for Read Mode \n");
		return status;
	}
	else
	{
		//DPRINTK("Set HIF_REG_13 with READ_OPCODE | FARADAY_PHY_ADDRESS Done!!\n");
	}

	// 2. Build value for HIF_REG14
        // Set Pend Flag, Reset Ready Flag & address of Reg.with in the PHY
        // Will procesed By MAC - MIIM Hardware.
        // Msb 1000 0000 Lsb - b7 Pend, b6 Ready,
        // b5 Not used,b4b3b2b1b0 Address of Reg with in the PHY

	status=0;
		mcs->checkval2[0]=0x0;
	mcs->checkval2[0] = HIF_REG_14_PEND_FLAG_BIT | (PhyRegIndex & 0x1F);
	status=SetVendorCommandPassive(mcs,HIF_REG_14,1,&mcs->checkval2[0]);//mcs->ByteValue);
	if(status<0)
	{
		//DPRINTK("ERROR : Setting pend flag & PHY reg.index in HIF_REG_14 to read phy \n");
		return status;
	}
	else
	{
		//DPRINTK(" Setting pend flag & PHY reg.index in HIF_REG_14 to read phy Done !!!\n");
	
	}
		mcs->checkval2[0]=0x0;

	// 3. Read (completion) Status for last command
        Count = 10;
        do
        {
		status=0;
		mcs->checkval2[0]=0x0;
                status = GetVendorCommandPassive(mcs,HIF_REG_14,1,&mcs->checkval2[0]);//(__u8 *)mcs->ByteValue);
		if(status<0)
	        {
                //DPRINTK("ERROR : Reading the ReadyFlag bit in the HIF_REG_14 \n");
                break;//command error
        	}
		else
		{
                //DPRINTK("Reading the ReadyFlag bit in the HIF_REG_14 DONE!!! \n");
			
		}

		//DPRINTK(" mcs->checkval2[0] value is %x\n",mcs->checkval2[0]);
		if (mcs->checkval2[0] & HIF_REG_14_READY_FLAG_BIT)
		{
			//DPRINTK("Command completed\n");
                        break; // command complete
		}
		else
		{
		
			Count -- ;
			//DPRINTK("READ PHY register command not Completed. Checking the READY flag again.\n");

			if (Count == 0 )
                        {
                 	
                                //DPRINTK("Checking the READY flag for 10 times completed not yet set.\n");
                                status = -1;
				//DPRINTK("Check1\n");
		                break;
                        }

		}
			

	}while(1);

	if(status<0)
	{
		//DPRINTK("Check2 \n");
		return status;
	}
	
	status=0;	
        //status = GetVendorCommandPassive(mcs,HIF_REG_11,2,(__u8 *)PhyRegValue);
        status = GetVendorCommandPassive(mcs,HIF_REG_11,2,PhyRegValue);
	if(status<0)
	{
		//DPRINTK("ERROR :Couldn't read HIF11-12 for phy data \n");
		return status;

	}
	return status;
}
static int WritePhyRegisterPassive(struct usbnet *mcs,__u8 PhyRegIndex,__u16 *PhyRegValue)
{

	int status=0,Count;
	mcs->WordValue = 0x0;
	//status=SetVendorCommandPassive(mcs,HIF_REG_11,2,(__u8 *)PhyRegValue);
	status=SetVendorCommandPassive(mcs,HIF_REG_11,2,PhyRegValue);
	if(status<0)
	{
		//DPRINTK("ERROR: couldn't write data in  register HIF_REG_11&12 \n");
		return status;
	}
	else
	{
		//DPRINTK(" Wrote data to register HIF_REG_11&12 \n");
		
		
	}
	status=0;
	mcs->checkval2[0]= WRITE_OPCODE | FARADAY_PHY_ADDRESS;
	//DPRINTK("in Local SetVendorCommandPassive reg is %x \tval is %x\n",HIF_REG_13,mcs->checkval2[0]);// *(mcs->ByteValue));
	status=SetVendorCommandPassive(mcs,HIF_REG_13,1,&mcs->checkval2[0]);//mcs->ByteValue);
	if(status<0)
	{
		//DPRINTK("ERROR :Couldn't set HIF13 for wRITE Mode \n");
		return status;
	}
	else
	{
		//DPRINTK("Set HIF_REG_13 with WRITE_OPCODE | FARADAY_PHY_ADDRESS Done!!\n");
	}

	// 2. Build value for HIF_REG14
        // Set Pend Flag, Reset Ready Flag & address of Reg.with in the PHY
        // Will procesed By MAC - MIIM Hardware.
        // Msb 1000 0000 Lsb - b7 Pend, b6 Ready,
        // b5 Not used,b4b3b2b1b0 Address of Reg with in the PHY

	status=0;
		mcs->checkval2[0]=0x0;
	mcs->checkval2[0] = HIF_REG_14_PEND_FLAG_BIT | (PhyRegIndex & 0x1F);
	status=SetVendorCommandPassive(mcs,HIF_REG_14,1,&mcs->checkval2[0]);//mcs->ByteValue);
	if(status<0)
	{
		//DPRINTK("ERROR : Setting pend flag & PHY reg.index in HIF_REG_14 to write phy \n");
		return status;
	}
	else
	{
		//DPRINTK(" Setting pend flag & PHY reg.index in HIF_REG_14 to write phy Done !!!\n");
	
	}
		mcs->checkval2[0]=0x0;

	// 3. Read (completion) Status for last command
        Count = 10;
        do
        {
		status=0;
		mcs->checkval2[0]=0x0;
                status = GetVendorCommandPassive(mcs,HIF_REG_14,1,&mcs->checkval2[0]);//(__u8 *)mcs->ByteValue);
		if(status<0)
	        {
                //DPRINTK("ERROR : Reading the ReadyFlag bit in the HIF_REG_14 \n");
                break;//command error
        	}
		else
		{
                //DPRINTK("Reading the ReadyFlag bit in the HIF_REG_14 DONE!!! \n");
			
		}

		//DPRINTK(" mcs->checkval2[0] value is %x\n",mcs->checkval2[0]);
		if (mcs->checkval2[0] & HIF_REG_14_READY_FLAG_BIT)
		{
			//DPRINTK("Command completed\n");
                        break; // command complete
		}
		else
		{
		
			Count -- ;
			//DPRINTK("READ PHY register command not Completed. Checking the READY flag again.\n");

			if (Count == 0 )
                        {
                 	
                                //DPRINTK("Checking the READY flag for 10 times completed not yet set.\n");
                                status = -1;
				//DPRINTK("Check1\n");
		                break;
                        }

		}
			

	}while(1);

	
	return status;
}


static int PrintAutoNegAdvRegister(struct usbnet *mcs)
{
	return 1;
}
	

static int AutoNegChangemode(struct usbnet *mcs,int ptrUserPhyMode)
{

	int status=0x0;
	__u16 AutoNegAdvtReg;
	__u8 ReadHifVal;	
  if( WITHOUT_PHY==0)
  {
	if(ptrUserPhyMode ==0)
	{
	
		// Writing 0x0021 in PhyAutoNeg Advertisement reg 4
		AutoNegAdvtReg = PHY_AUTONEGADVT_FdxPause | \
					PHY_AUTONEGADVT_Fdx100TX |\
                                        PHY_AUTONEGADVT_100TX | PHY_AUTONEGADVT_ieee802_3|\
                                                PHY_AUTONEGADVT_10TFdx|PHY_AUTONEGADVT_10T;
	}
	else if(ptrUserPhyMode ==1)
	{
		// Writing 0x0021 in PhyAutoNeg Advertisement reg 4
                AutoNegAdvtReg = PHY_AUTONEGADVT_10T | PHY_AUTONEGADVT_ieee802_3;
	}
	else if(ptrUserPhyMode ==2)
	{
		// Writing 0x0461 in PhyAutoNeg Advertisement reg 4
                AutoNegAdvtReg = PHY_AUTONEGADVT_FdxPause | PHY_AUTONEGADVT_10TFdx |\
                                                  PHY_AUTONEGADVT_10T | PHY_AUTONEGADVT_ieee802_3;

	}
	else if(ptrUserPhyMode ==3)
	{
		// Writing 0x0081 in PhyAutoNeg Advertisement reg 4
                AutoNegAdvtReg = PHY_AUTONEGADVT_100TX | PHY_AUTONEGADVT_ieee802_3;

	}
	else if(ptrUserPhyMode ==4)
	{
		// Writing 0x0581 in PhyAutoNeg Advertisement reg 4
                AutoNegAdvtReg = PHY_AUTONEGADVT_FdxPause | PHY_AUTONEGADVT_Fdx100TX |\
                                            PHY_AUTONEGADVT_100TX | PHY_AUTONEGADVT_ieee802_3;
	}
	//DPRINTK("in AutoNegChangemode  AutoNegAdvtReg is %04x \n", AutoNegAdvtReg);
	status=0x0;
	status=WritePhyRegisterPassive(mcs,PHY_AUTONEGADVT_REG_INDEX,&AutoNegAdvtReg);
	//DPRINTK("Status of WritePhyRegisterPassive ANG is %x\n",status);
	if(status >=0)
        {
                //DPRINTK("Writing value for AutoNegotiation in AutoNegAdvt Register() success\n");
		//break;

        }
	else
	{	
                //DPRINTK("Writing value for AutoNegotiation in AutoNegAdvt Register() FAILURE\n");
                       mcs7830_disconnect(mcs->udev, (void *) mcs);
		return -1;//NULL;
		}
	//////////////////Change For Link Status Problem :Begin ///////////
                       //First Disable All
               mcs->PhyControlReg =  0x0000;
	status=0x0;
               status = WritePhyRegisterPassive(mcs,PHY_CONTROL_REG_INDEX,&mcs->PhyControlReg);
	if(status >=0)
               {
                       //DPRINTK("Writing value WritePhyControlRegister() success\n");
                       //break;
                }
               else
               {
                       //DPRINTK("Writing value for WritePhyControlRegister() FAILURE\n");
                       mcs7830_disconnect(mcs->udev, (void *) mcs);
                       return -1;//NULL;
                }

	mcs->PhyControlReg =  PHY_CONTROL_AUTONEG_ENABLE;
	status=0x0;
               status = WritePhyRegisterPassive(mcs,PHY_CONTROL_REG_INDEX,&mcs->PhyControlReg);
	if(status >=0)
	{
        	//DPRINTK("Writing value WritePhyControlRegister() ANG enable success\n");
                //break;
        }
        else
        {
                //DPRINTK("Writing value for WritePhyControlRegister() SNG enable FAILURE\n");
                mcs7830_disconnect(mcs->udev, (void *) mcs);
                return -1;//NULL;
        }

	//Restart Auto Neg (Keep the Enable Auto Neg Bit Set)
        mcs->PhyControlReg =  PHY_CONTROL_AUTONEG_ENABLE |PHY_CONTROL_RESTART_AUTONEG;
	status=0x0;
        status = WritePhyRegisterPassive(mcs,PHY_CONTROL_REG_INDEX,&mcs->PhyControlReg);

	if(status >=0)
        {
        	//DPRINTK("Writing value WritePhyControlRegister() ANG enable&restart success\n");
                //break;

        }
        else
        {
               //DPRINTK("Writing value for WritePhyControlRegister() SNG enable&restart FAILURE\n");
               mcs7830_disconnect(mcs->udev, (void *) mcs);
               return -1;//NULL;

        }

	mcs->bAutoNegStarted = TRUE;
	//////////////////Change For Link Status Problem :End ///////////

	
	status=0x0;
	if(mcs->PhyIdentity == INTEL_PHY)
        {
        status = ReadPhyRegisterPassive(mcs,PHY_CHIPSTATUS_REG_INDEX,&mcs->TempPhyControlReg);
        }
        else if(mcs->PhyIdentity == FARADAY_PHY)
        {

        status = ReadPhyRegisterPassive(mcs,PHY_CONTROL_REG_INDEX,&mcs->TempPhyControlReg);
	}
	if(status >=0)
        {
		//DPRINTK("PhyControl for AutoNegotiation Value: x%04x\n", mcs->TempPhyControlReg);
                //break;
        }
        else
        {
                //DPRINTK("Reading value from ReadPhyControlRegister() FAILURE FAILURE\n");
                mcs7830_disconnect(mcs->udev, (void *) mcs);
                return -1;//NULL;
        }
	// read linkspeed & duplex from PHY & set to HIF
	AutoNegAdvtReg=0x0;
	status=0x0;
        status = ReadPhyRegisterPassive(mcs,PHY_AUTONEGADVT_REG_INDEX,&AutoNegAdvtReg);
	if(status >=0)
        {
		//DPRINTK("in AutoNegChangemode  AutoNegAdvtReg is %04x \n", AutoNegAdvtReg);
                //break;
        }
        else
        {
		//DPRINTK("in AutoNegChangemode  AutoNegAdvtReg FAILED\n");
                mcs7830_disconnect(mcs->udev, (void *) mcs);
                return -1;//NULL;
        }


          if(AutoNegAdvtReg & PHY_AUTONEGADVT_100TX) 
	 mcs->HifReg15 |=  HIF_REG_15_SPEED100; 
	else
		mcs->HifReg15 &= ~HIF_REG_15_SPEED100;


	if((AutoNegAdvtReg & PHY_AUTONEGADVT_10TFdx)||(AutoNegAdvtReg & PHY_AUTONEGADVT_Fdx100TX)) 
		 mcs->HifReg15 |= HIF_REG_15_FULLDUPLEX_ENABLE;
	else
		mcs->HifReg15 &= ~HIF_REG_15_FULLDUPLEX_ENABLE;


	status=0x0;
	status=SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
	//DPRINTK("in AutoNegChangemode  Writing mcs->HifReg15 is %04x \n",mcs->HifReg15 );
	if(status >=0)
        {
		//DPRINTK("in AutoNegChangemode  writing mcs->HifReg15 SUCCESS\n" );
                //break;
        }
        else
        {
		//DPRINTK("in AutoNegChangemode  writing mcs->HifReg15 FAILED\n");
                mcs7830_disconnect(mcs->udev, (void *) mcs);
                return -1;//NULL;
        }
	status=0;
	status=GetVendorCommandPassive( mcs,HIF_REG_15,1,&ReadHifVal);
	//DPRINTK("in AutoNegChangemode  Read mcs->HifReg15 is %04x \n",ReadHifVal );
} // WITHOUT_PHY end
	return status;		


	//DPRINTK("Phy Status Register Value: x%04x\n", mcs->PhyStatusReg);
}

	
static int ANGInitializeDev(struct usbnet *mcs)
{
        int	Ccnt=0;
	__u16	Read_HIFReg_22; 
	__u8	SingleByte;
	int 	status;
	 __u16   PhyIDReg1 = 0x0;
        __u16   PhyIDReg2 = 0x0;


	mcs->DeviceReleaseNumber = DEVICE_REV_B; ///by default revision B
        
	// Check for other revision devices by reading one of the additional registers that are 
	// existing.
        // Here, we are reading HIFReg_22 for the above mentioned purpose
	do{
		status = GetVendorCommandPassive(mcs,0x15,2,&Read_HIFReg_22);
		if(status >0)//STATUS_SUCCESS)
	        {
	                DPRINTK("Device is of revision C\n");
			mcs->DeviceReleaseNumber = DEVICE_REV_C;
			break;
        	}
		Ccnt++;
		//udelay(50);
	}while(Ccnt>2);

	Ccnt=5;
	do{
		status=0x0;
		status = MosUsbGetPermanentAddress(mcs);
		Ccnt--;
	}while(Ccnt>0);
	if(status >=0)
	{
                DPRINTK("vendor command MosUsbGetPermanentAddress success\n");
		//DPRINTK("address is %x\n",mcs->AiPermanentNodeAddress);
		
	}


// External_Phy

/* code for External PHY implementation */ 

        // Reading PhyID Reg1
        status = ReadPhyRegisterPassive(mcs,PHY_IDENTIFICATION1_REG_INDEX,&PhyIDReg1);
        //DPRINTK("PhyIDReg1 is 0x%x,status=%d \n",PhyIDReg1,status);
        if(status >=0)
                DPRINTK("Reading PHY_IDENTIFICATION1_REG_INDEX success...\n");
        else
                DPRINTK("Reading PHY_IDENTIFICATION1_REG_INDEX failure...\n");
         // Reading PhyID Reg2
        status = ReadPhyRegisterPassive(mcs,PHY_IDENTIFICATION2_REG_INDEX,&PhyIDReg2);
        //DPRINTK("PhyIDReg2 is 0x%x, status= %d \n",PhyIDReg2,status);
        if(status >= 0)
                DPRINTK("Reading PHY_IDENTIFICATION2_REG_INDEX success...\n");
        else
                DPRINTK("Reading PHY_IDENTIFICATION2_REG_INDEX failure...\n");
        /* validate the external PHY */
        if( (PhyIDReg1 == INTEL_PHY_ID1) && (PhyIDReg2 == INTEL_PHY_ID2) )
        {
                DPRINTK(" INTEL_PHY detected \n");
                mcs->PhyIdentity = INTEL_PHY;
                //DPRINTK("\n Writing 0x0080 in  PHY_CONFIG_REG_INDEX REG 19 \n");
        //      WritePhyRegisterPassive(mcs,PHY_CONFIG_REG_INDEX, 0x0080); // check
        }
        else
	{
                DPRINTK(" FARADAY_PHY detected \n");
		 mcs->PhyIdentity =FARADAY_PHY;
	}
	

	// Check whether we have to do AutoNegotiation or the USER has forced
        // us into one mode.
        //if ( *(MosUsbContext->ptrUserPhyMode) == USER_SET_AUTONEG )

	if(1)
	{
	
	if( WITHOUT_PHY == 0)
	{
		status=0x0;
		status=ReadPhyRegisterPassive(mcs,PHY_AUTONEGADVT_REG_INDEX,&mcs->PhyAutoNegAdvReg);
		DPRINTK("Status of ReadPhyRegisterPassive is %x\n",status);
		if(status >=0)
	        {
	                DPRINTK("ReadPhyRegisterPassive success\n");
			//break;
	
	        }
		else
		{	
	                DPRINTK("ReadPhyRegisterPassive fail\n");
                        mcs7830_disconnect(mcs->udev, (void *) mcs);
			return -1;//NULL;

		}
	} // end of WITHOUT_PHY
		PrintAutoNegAdvRegister(mcs);
		//static int AutoNegChangemode(struct mcs7830_cb *mcs,int ptrUserPhyMode)
		status=0x0;
		status=AutoNegChangemode(mcs,0);//0x05e1
		if(status>=0)
		DPRINTK("Auto negotiation staarted\n");
		
		//DPRINTK("Phy Status Register Value: x%04x\n", mcs->PhyStatusReg);

	}

	////////////////////////////

	else
	{
        
	#ifdef comment
		if(interest==1)
		AutoNegChangemode(mcs,1);//0x05e1
		if(interest==2)
		AutoNegChangemode(mcs,2);//0x05e1
		if(interest==3)
		AutoNegChangemode(mcs,3);//0x05e1
		if(interest==4)
		AutoNegChangemode(mcs,4);//0x05e1
		




		DBGPRINT(DBG_COMP_USBVENDOR, DBG_LEVEL_ERR,
                                ("Phy Status Register Value: x%04x\n", MosUsbContext->PhyStatusReg));

                //Updating Link Speed for 10Hdx, 10Fdx, 100Hdx and 100Fdx
                MosUsbContext->LinkSpeed =
                        AutoNegAdvtReg & PHY_AUTONEGADVT_100TX ? 1000000:100000;

	#endif

	} // end of else  (UserPhyMode)

	//Rev.C change

  if( WITHOUT_PHY == 0)
  {
	mcs->ptrFpgaVersion=PTR_FPGA_VERSION;
        if (mcs->ptrFpgaVersion != 0)
                mcs->HifReg15 |=  HIF_REG_15_CFG; //need to be checked!!!may be not needed in Linux driver

	// NOTE:!!!! neeed to read HifReg15 previous values!!!

    	// enable Rx & Tx register
	mcs->HifReg15 |= (HIF_REG_15_TXENABLE| HIF_REG_15_RXENABLE );

        // Temp enable Multicast bit at initialization time. It should be done
        // when driver gets the packetfilter OID.
        mcs->HifReg15 |=  HIF_REG_15_ALLMULTICAST ;

        DPRINTK("HIF Register 15 %04x \n",mcs->HifReg15);


    	// write these values to HIF
	status=0x0;
	status=SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
        if (status>=0)
	{
        	DPRINTK (" MosUsbStartDevice() UpdateHifReg15() success\n");
	}
	else
        {
                DPRINTK("ERROR: MosUsbStartDevice() UpdateHifReg15() FAILURE (%x)\n", status);
		mcs7830_disconnect(mcs->udev, (void *) mcs);
                return -1;//NULL;	
        }

  }

	if(WITHOUT_PHY == 1)
	{
 	 //for with_out PHY mode we are directly initializing HIF_REG_15 with 0xF8.
       		status = 0;
        	mcs->HifReg15 = 0xF8;
        	status=SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
        	if (status>=0)
        	        DPRINTK (" writing HifReg15() 0xF8 is success\n");

	}	


//#ifndef MCS7830_WHQL

        //Only if we are in 10 Half mode
        if( (!(mcs->HifReg15 & HIF_REG_15_FULLDUPLEX_ENABLE)) &&
                (!(mcs->HifReg15 & HIF_REG_15_SPEED100 )) )
        {
                // Set 40 in HIF register 9
                SingleByte = 40;
                SetVendorCommandPassive( mcs,HIF_REG_09,1,&SingleByte);


                // Set 32 in HIF register 10
                SingleByte = 32;
                SetVendorCommandPassive( mcs,HIF_REG_10,1,&SingleByte);
        }


//#ifndef MCS7830_WHQL
      // for revision versions 'C' and above
	(mcs->ptrPauseThreshold) = PTR_PAUSE_THRESHOLD;
        if (mcs->DeviceReleaseNumber == DEVICE_REV_C)
        {
                    DPRINTK("****** PauseThreshold = %d\n", mcs->ptrPauseThreshold) ;

                // Writing pause data to the device
                SetVendorCommandPassive( mcs,HIF_REG_23,1,&mcs->ptrPauseThreshold);
        }


	return status;
}

static int mdio_read (struct net_device *dev, int phy_id, int location)
{
        int status;
	struct usbnet *mcs=dev->priv;
	__u16 PhyStatusRegValue,phyControlReg;
	status=0;
	mdelay(500);
	if( WITHOUT_PHY == 0)
	{
		if(mcs->PhyIdentity == INTEL_PHY)
			status=ReadPhyRegisterPassive(mcs,PHY_CHIPSTATUS_REG_INDEX,&phyControlReg);
		else if(mcs->PhyIdentity == FARADAY_PHY)
		{
			status=ReadPhyRegisterPassive(mcs,PHY_CONTROL_REG_INDEX,&phyControlReg);
		}
	}
	
	DPRINTK("mdio_read:location is %d\n",location);
	if(location==0x0)// ||(location==0x4))
	{
	
	   if( WITHOUT_PHY== 1)
		return BMCR_SPEED100|ADVERTISE_100FULL|ADVERTISE_CSMA; //testing with hotcode
	
	   if( WITHOUT_PHY ==0)
	   {
		if(mcs->PhyIdentity == INTEL_PHY)
                {
                        printk("%s 1 read reg is %x\n",__FUNCTION__,phyControlReg);
                        if(phyControlReg & PHY_CHIPSTATUS_REG_SPEED100)//PHY_CONTROL_SPEED100)
                        {
                                if( phyControlReg & PHY_CHIPSTATUS_REG_FULLDUPLEX_ENABLE)//PHY_CONTROL_FULLDUPLEX )
                                {
                                        DPRINTK("mdio_read: Duplex id FullDuplex\n");
                                        mcs->HifReg15 |= HIF_REG_15_FULLDUPLEX_ENABLE;
                                        mcs->HifReg15 |= HIF_REG_15_SPEED100;
                                        SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
                                        return BMCR_SPEED100|ADVERTISE_100FULL|ADVERTISE_CSMA;
                                }
                                else
                                {
                                        DPRINTK("mdio_read: Duplex id HalfDuplex\n");
                                        mcs->HifReg15 &= ~HIF_REG_15_FULLDUPLEX_ENABLE;
                                        mcs->HifReg15 |= HIF_REG_15_SPEED100;
                                        SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
                                        return BMCR_SPEED100|ADVERTISE_100HALF|ADVERTISE_CSMA;
                                }
                        }
                        else
                        {
                                if( phyControlReg & PHY_CHIPSTATUS_REG_FULLDUPLEX_ENABLE)//PHY_CONTROL_FULLDUPLEX )
                                {
                                        DPRINTK("mdio_read: Duplex id FullDuplex\n");
                                        mcs->HifReg15 |= HIF_REG_15_FULLDUPLEX_ENABLE;
                                        mcs->HifReg15 &= ~HIF_REG_15_SPEED100;
                                        SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
                                        return BMCR_FULLDPLX|ADVERTISE_10FULL|ADVERTISE_CSMA;
                                }
                                else
                                {
                                        DPRINTK("mdio_read: Duplex id HalfDuplex\n");
                                        mcs->HifReg15 &= ~HIF_REG_15_FULLDUPLEX_ENABLE;
                                        mcs->HifReg15 &= ~HIF_REG_15_SPEED100;
                                        SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
                                        return ADVERTISE_10HALF|ADVERTISE_CSMA;
                                }

                        }


                }

	
		else if(mcs->PhyIdentity == FARADAY_PHY)
                {
	
			if(phyControlReg & PHY_CONTROL_SPEED100)
			{
				if( phyControlReg & PHY_CONTROL_FULLDUPLEX )
				{
					DPRINTK("mdio_read: Duplex id FullDuplex\n");
					mcs->HifReg15 |= HIF_REG_15_FULLDUPLEX_ENABLE;
					mcs->HifReg15 |= HIF_REG_15_SPEED100;
					SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
					return BMCR_SPEED100|ADVERTISE_100FULL|ADVERTISE_CSMA;
				}
				else
				{
					DPRINTK("mdio_read: Duplex id HalfDuplex\n");
					mcs->HifReg15 &= ~HIF_REG_15_FULLDUPLEX_ENABLE;
					mcs->HifReg15 |= HIF_REG_15_SPEED100;
					SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
					return BMCR_SPEED100|ADVERTISE_100HALF|ADVERTISE_CSMA;
				}
			}
			else
			{
				if( phyControlReg & PHY_CONTROL_FULLDUPLEX )
				{
					DPRINTK("mdio_read: Duplex id FullDuplex\n");
					mcs->HifReg15 |= HIF_REG_15_FULLDUPLEX_ENABLE;
					mcs->HifReg15 &= ~HIF_REG_15_SPEED100;
					SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
					return BMCR_FULLDPLX|ADVERTISE_10FULL|ADVERTISE_CSMA;
				}
				else
				{
					DPRINTK("mdio_read: Duplex id HalfDuplex\n");
					mcs->HifReg15 &= ~HIF_REG_15_FULLDUPLEX_ENABLE;
					mcs->HifReg15 &= ~HIF_REG_15_SPEED100;
					SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
					return ADVERTISE_10HALF|ADVERTISE_CSMA;
				}
	
			}

		}
		
	  } 	// END OF WITHOUT_PHY

	}


	if(location ==0x1)
	{
	  	if( WITHOUT_PHY == 1)
	  	{ // just return LINKOK in without_phy mode
			DPRINTK("mdio_read: Link is OK\n");
			return LINKOK;
	  	}
		if( WITHOUT_PHY ==0)
		{	
			status=0;
			status=ReadPhyRegisterPassive(mcs,PHY_STATUS_REG_INDEX,&PhyStatusRegValue);
			if(PhyStatusRegValue & PHY_STATUS_REG_LINK_STATUS)
			{
				DPRINTK("mdio_read: Link is OK\n");
				return LINKOK;
			}
			else
			{
				DPRINTK("mdio_read: Link no link\n");
				return 0;
			}
		}
	}



/*	
	status=GetVendorCommandPassive( mcs,HIF_REG_15,1,&ReadHifVal);
	//DPRINTK("in mdio_read  Read mcs->HifReg15 is %04x \n",ReadHifVal );
	DPRINTK("mdio_read: location is %x\n",location);
	if((location==0x0) ||(location==0x4))
	{
	if(ReadHifVal & HIF_REG_15_SPEED100) //100 Mbps
	{
		//DPRINTK(" mdio_read: Running in 100Mbps Mode\n");
		
		val |= BMCR_SPEED100;//BIT_13;
		if(ReadHifVal & HIF_REG_15_FULLDUPLEX_ENABLE)
		{
			DPRINTK(" mdio_read: Running in 100Mbps Full Duplex Mode\n");
			val2 |= (ADVERTISE_100FULL|ADVERTISE_CSMA);// (BIT_24 | BIT_16);
			
		}
		else
		{
			DPRINTK(" mdio_read: Running in 100Mbps Half Duplex Mode\n");
			val2 |= (ADVERTISE_100HALF |ADVERTISE_CSMA);// (BIT_23 | BIT_16);
	        
		}
	}

	else //10 Mbps
	{
		//DPRINTK(" mdio_read: Running in 10Mbps Mode\n");

		if(ReadHifVal & HIF_REG_15_FULLDUPLEX_ENABLE)
		{
			DPRINTK(" mdio_read: Running in 10Mbps Full Duplex Mode\n");
			val2 |= (ADVERTISE_10FULL | ADVERTISE_CSMA);// (BIT_22 | BIT_16);
		}
		else
		{
			DPRINTK(" mdio_read: Running in 10Mbps Half Duplex Mode\n");
			val2  |= ( ADVERTISE_10HALF|ADVERTISE_CSMA);// (BIT_21 | BIT_16);
		}
	}

	}
	if(location==0x0)
	{
			//DPRINTK("mdio_read: Speed val is %04x\n",(val & 0x0000ffff));
			DPRINTK("mdio_read: Speed val is %04x\n",val);

	 //return (val & 0x0000ffff);
	 return val;
	}
        if(location==0x1)  
	{
		status=0;
		status = ReadPhyRegisterPassive(mcs,PHY_STATUS_REG_INDEX,&PhyStatusRegValue);
		if(PhyStatusRegValue & PHY_STATUS_REG_LINK_STATUS)
			return LINKOK;
		else
			return 0;
	}
        if(location==0x4)
	{
			//DPRINTK("mdio_read:Duplex val is %04x\n",((val2 & 0xffff0000) >> 16));
			DPRINTK("mdio_read:Duplex val is %04x\n",val2 );

	 //return ((val2 & 0xffff0000) >> 16);
	 return val2;
	}
	*/
	return 0;

}

static void mdio_write (struct net_device *dev, int phy_id, int location,
                int val)
{

        struct usbnet *mcs=dev->priv;
        DPRINTK(" val:0x%x location: 0x%x\n",val,location);
        DPRINTK("\n");
        if(val & 0x1000)
        {

		DPRINTK("mdio_write: Trying  to set 100Full\n");
		AutoNegChangemode(mcs,0); //Auto Negotiation
                mcs->SpeedDuplex=0;
        }
        else
        {
		
                if(val & 0x2000) // 100 mbs or 10 mbs
                {
			if(val & 0x100)
			{
			//100 Full
			DPRINTK("mdio_write:  Trying  to set 100Full\n");
			AutoNegChangemode(mcs,4);
			
			mcs->ForceSpeed=100;
                        mcs->ForceDuplex=1;
				
			}
			else
			{
			//100 Half
			DPRINTK(" mdio_write: Trying  to set 100Half\n");
			AutoNegChangemode(mcs,3);//0x05e1
			mcs->ForceSpeed=100;
                        mcs->ForceDuplex=0;
			
			}
                }
                else
                {
			if(val & 0x100)
			{
			//10 Full
			DPRINTK("mdio_write: Trying  to set 10Full\n");
			AutoNegChangemode(mcs,2);//0x05e1
			mcs->ForceSpeed=10;
                        mcs->ForceDuplex=1;
				
			}
			else
			{
			//10 Half
			DPRINTK("mdio_write: Trying  to set 10Half\n");
			AutoNegChangemode(mcs,1);//0x05e1
			mcs->ForceSpeed=10;
                        mcs->ForceDuplex=0;
			
			}

                }

                mcs->SpeedDuplex=1;
        }
        return;
}



static void mcs7830_disconnect (struct usb_device *udev, void *ptr)
{
        struct usbnet *mcs = (struct usbnet *) ptr;
        //mcs->present=0;

        if (mcs->net) 
	{
		unregister_netdev (mcs->net);
                mcs->net = NULL;
        }

        mcs->udev=NULL;
	

        DPRINTK(" USB device MCS7830 device is removed \n");

        usb_put_dev (udev);

}





/*-------------------------------------------------------------------------
 *
 * Network Device Driver (peer link to "Host Device", from USB host)
 *
 *-------------------------------------------------------------------------*/

static int usbnet_change_mtu (struct net_device *net, int new_mtu)
{
	struct usbnet	*dev = netdev_priv(net);

	if (new_mtu <= MIN_PACKET || new_mtu > MAX_PACKET)
		return -EINVAL;
	// no second zero-length packet read wanted after mtu-sized packets
	if (((new_mtu + sizeof (struct ethhdr)) % dev->maxpacket) == 0)
		return -EDOM;
	net->mtu = new_mtu;
	return 0;
}

/*-------------------------------------------------------------------------*/

static struct net_device_stats *usbnet_get_stats (struct net_device *net)
{
	struct usbnet	*dev = netdev_priv(net);
	return &dev->stats;
}

/*-------------------------------------------------------------------------*/

/* some LK 2.4 HCDs oopsed if we freed or resubmitted urbs from
 * completion callbacks.  2.5 should have fixed those bugs...
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,14)
static void defer_bh (struct usbnet *dev, struct sk_buff *skb)
{
	struct sk_buff_head	*list = skb->list;
#else
static void defer_bh (struct usbnet *dev, struct sk_buff *skb,struct sk_buff_head *list)
{

#endif
	unsigned long		flags;

	spin_lock_irqsave (&list->lock, flags);
	__skb_unlink (skb, list);
	spin_unlock (&list->lock);
	spin_lock (&dev->done.lock);
	__skb_queue_tail (&dev->done, skb);
	if (dev->done.qlen == 1)
		tasklet_schedule (&dev->bh);
	spin_unlock_irqrestore (&dev->done.lock, flags);
}

/* some work can't be done in tasklets, so we use keventd
 *
 * NOTE:  annoying asymmetry:  if it's active, schedule_work() fails,
 * but tasklet_schedule() doesn't.  hope the failure is rare.
 */
static void defer_kevent (struct usbnet *dev, int work)
{
	set_bit (work, &dev->flags);
	if (!schedule_work (&dev->kevent))
		deverr (dev, "kevent %d may have been dropped", work);
	else
		devdbg (dev, "kevent %d scheduled", work);
}

/*-------------------------------------------------------------------------*/

static void rx_complete (struct urb *urb, struct pt_regs *regs);

static void rx_submit (struct usbnet *dev, struct urb *urb, int flags)
{
	struct sk_buff		*skb;
	struct skb_data		*entry;
	int			retval = 0;
	unsigned long		lockflags;
	size_t			size;
	//DPRINTK(" in the function rx_submit start\n");
		//size = (sizeof (struct ethhdr) + dev->net->mtu); Old Line 
		size = (sizeof (struct ethhdr) + dev->net->mtu+1);
	//DPRINTK("in the function rx_submit submited size is %d\n",size);
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,10)
	if ((skb = alloc_skb (size, flags)) == NULL) {
	#endif
	#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,10)
	if ((skb = alloc_skb (size + NET_IP_ALIGN, flags)) == NULL) {
	#endif
		if (netif_msg_rx_err (dev))
			devdbg (dev, "no rx skb");
		defer_kevent (dev, EVENT_RX_MEMORY);
		usb_free_urb (urb);
		return;
	}
	#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,10)
	skb_reserve (skb, NET_IP_ALIGN);
	#endif

	entry = (struct skb_data *) skb->cb;
	entry->urb = urb;
	entry->dev = dev;
	entry->state = rx_start;
	entry->length = 0;

	usb_fill_bulk_urb (urb, dev->udev, dev->in,
		skb->data, size, rx_complete, skb);
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,14)
	urb->transfer_flags |= URB_ASYNC_UNLINK;
	#endif

	spin_lock_irqsave (&dev->rxq.lock, lockflags);

	if (netif_running (dev->net)
			&& netif_device_present (dev->net)
			&& !test_bit (EVENT_RX_HALT, &dev->flags)) {
		switch (retval = usb_submit_urb (urb, GFP_ATOMIC)){ 
		case -EPIPE:
			defer_kevent (dev, EVENT_RX_HALT);
			break;
		case -ENOMEM:
			defer_kevent (dev, EVENT_RX_MEMORY);
			break;
		case -ENODEV:
			if (netif_msg_ifdown (dev))
				devdbg (dev, "device gone");
			netif_device_detach (dev->net);
			break;
		default:
			if (netif_msg_rx_err (dev))
				devdbg (dev, "rx submit, %d", retval);
			tasklet_schedule (&dev->bh);
			break;
		case 0:
			__skb_queue_tail (&dev->rxq, skb);
		}
	} else {
		if (netif_msg_ifdown (dev))
			devdbg (dev, "rx: stopped");
		retval = -ENOLINK;
	}
	spin_unlock_irqrestore (&dev->rxq.lock, lockflags);
	if (retval) {
		dev_kfree_skb_any (skb);
		usb_free_urb (urb);
	}
}


/*-------------------------------------------------------------------------*/

static inline void rx_process (struct usbnet *dev, struct sk_buff *skb)
{
	//DPRINTK("in the function rx_process \n");
	if (dev->driver_info->rx_fixup
			&& !dev->driver_info->rx_fixup (dev, skb))
		goto error;
	// else network stack removes extra byte if we forced a short packet

	if (skb->len)
		skb_return (dev, skb);
	else {
		if (netif_msg_rx_err (dev))
			devdbg (dev, "drop");
error:
		dev->stats.rx_errors++;
		skb_queue_tail (&dev->done, skb);
	}
}

/*-------------------------------------------------------------------------*/

static void rx_complete (struct urb *urb, struct pt_regs *regs)
{
	struct sk_buff		*skb = (struct sk_buff *) urb->context;
	struct skb_data		*entry = (struct skb_data *) skb->cb;
	struct usbnet		*dev = entry->dev;
	int			urb_status = urb->status;
	//DPRINTK("in the function rx_complete \n");
	skb_put (skb, urb->actual_length);
	entry->state = rx_done;
	entry->urb = NULL;

	switch (urb_status) {
	    // success
	    case 0:
		if (MIN_PACKET > skb->len || skb->len > MAX_PACKET) {
			entry->state = rx_cleanup;
			dev->stats.rx_errors++;
			dev->stats.rx_length_errors++;
			if (netif_msg_rx_err (dev))
				devdbg (dev, "rx length %d", skb->len);
		}
		break;

	    // stalls need manual reset. this is rare ... except that
	    // when going through USB 2.0 TTs, unplug appears this way.
	    // we avoid the highspeed version of the ETIMEOUT/EILSEQ
	    // storm, recovering as needed.
	    case -EPIPE:
		dev->stats.rx_errors++;
		defer_kevent (dev, EVENT_RX_HALT);
		// FALLTHROUGH

	    // software-driven interface shutdown
	    case -ECONNRESET:		// async unlink
	    case -ESHUTDOWN:		// hardware gone
		if (netif_msg_ifdown (dev))
			devdbg (dev, "rx shutdown, code %d", urb_status);
		goto block;

	    // we get controller i/o faults during khubd disconnect() delays.
	    // throttle down resubmits, to avoid log floods; just temporarily,
	    // so we still recover when the fault isn't a khubd delay.
	    case -EPROTO:		// ehci
	    case -ETIMEDOUT:		// ohci
	    case -EILSEQ:		// uhci
		dev->stats.rx_errors++;
		if (!timer_pending (&dev->delay)) {
			mod_timer (&dev->delay, jiffies + THROTTLE_JIFFIES);
			if (netif_msg_link (dev))
				devdbg (dev, "rx throttle %d", urb_status);
		}
block:
		entry->state = rx_cleanup;
		entry->urb = urb;
		urb = NULL;
		break;

	    // data overrun ... flush fifo?
	    case -EOVERFLOW:
		dev->stats.rx_over_errors++;
		// FALLTHROUGH
	    
	    default:
		entry->state = rx_cleanup;
		dev->stats.rx_errors++;
		if (netif_msg_rx_err (dev))
			devdbg (dev, "rx status %d", urb_status);
		break;
	}

	#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,14)
	defer_bh (dev, skb);
	#else
	defer_bh (dev, skb,&dev->rxq);
	#endif

	if (urb) {
		if (netif_running (dev->net)
				&& !test_bit (EVENT_RX_HALT, &dev->flags)) {
			rx_submit (dev, urb, GFP_ATOMIC);
			return;
		}
		usb_free_urb (urb);
	}
	if (netif_msg_rx_err (dev))
		devdbg (dev, "no read resubmitted");
}

 #if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,20)
static void intr_complete (struct urb *urb, struct pt_regs *regs)
#else
static void intr_complete (struct urb *urb )
#endif
{
	struct usbnet	*dev = urb->context;
	int		status = urb->status;

	switch (status) {
	    /* success */
	    case 0:
		dev->driver_info->status(dev, urb);
		break;

	    /* software-driven interface shutdown */
	    case -ENOENT:		// urb killed
	    case -ESHUTDOWN:		// hardware gone
		if (netif_msg_ifdown (dev))
			devdbg (dev, "intr shutdown, code %d", status);
		return;

	    /* NOTE:  not throttling like RX/TX, since this endpoint
	     * already polls infrequently
	     */
	    default:
		devdbg (dev, "intr status %d", status);
		break;
	}

	if (!netif_running (dev->net))
		return;

	memset(urb->transfer_buffer, 0, urb->transfer_buffer_length);
	status = usb_submit_urb (urb, GFP_ATOMIC);
	if (status != 0 && netif_msg_timer (dev))
		deverr(dev, "intr resubmit --> %d", status);
}

/*-------------------------------------------------------------------------*/

// unlink pending rx/tx; completion handlers do all other cleanup

static int unlink_urbs (struct usbnet *dev, struct sk_buff_head *q)
{
	unsigned long		flags;
	struct sk_buff		*skb, *skbnext;
	int			count = 0;

	spin_lock_irqsave (&q->lock, flags);
	for (skb = q->next; skb != (struct sk_buff *) q; skb = skbnext) {
		struct skb_data		*entry;
		struct urb		*urb;
		int			retval;

		entry = (struct skb_data *) skb->cb;
		urb = entry->urb;
		skbnext = skb->next;

		// during some PM-driven resume scenarios,
		// these (async) unlinks complete immediately
		retval = usb_unlink_urb (urb);
		if (retval != -EINPROGRESS && retval != 0)
			devdbg (dev, "unlink urb err, %d", retval);
		else
			count++;
	}
	spin_unlock_irqrestore (&q->lock, flags);
	return count;
}


/*-------------------------------------------------------------------------*/

// precondition: never called in_interrupt

static int usbnet_stop (struct net_device *net)
{
	struct usbnet		*dev = netdev_priv(net);
	int			temp;
	DECLARE_WAIT_QUEUE_HEAD (unlink_wakeup); 
	DECLARE_WAITQUEUE (wait, current);
	DPRINTK("START of the function usbnet_stop\n");
	DPRINTK("netif_stop_queue in the function usbnet_stop\n");
	netif_stop_queue (net);

	if (netif_msg_ifdown (dev))
		devinfo (dev, "stop stats: rx/tx %ld/%ld, errs %ld/%ld",
			dev->stats.rx_packets, dev->stats.tx_packets, 
			dev->stats.rx_errors, dev->stats.tx_errors
			);

	// ensure there are no more active urbs
	add_wait_queue (&unlink_wakeup, &wait);
	dev->wait = &unlink_wakeup;
	temp = unlink_urbs (dev, &dev->txq) + unlink_urbs (dev, &dev->rxq);

	// maybe wait for deletions to finish.
	while (skb_queue_len (&dev->rxq)
			&& skb_queue_len (&dev->txq)
			&& skb_queue_len (&dev->done)) {
	#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,10)
		msleep(UNLINK_TIMEOUT_MS);
	#endif
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,10)
	 set_current_state (TASK_UNINTERRUPTIBLE);
         schedule_timeout (UNLINK_TIMEOUT_JIFFIES);

	#endif
		if (netif_msg_ifdown (dev))
			devdbg (dev, "waited for %d urb completions", temp);
	}
	dev->wait = NULL;
	remove_wait_queue (&unlink_wakeup, &wait); 

	#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,10)
	usb_kill_urb(dev->interrupt);
	#endif
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,10)
	usb_unlink_urb(dev->interrupt);
	#endif
	/* deferred work (task, timer, softirq) must also stop.
	 * can't flush_scheduled_work() until we drop rtnl (later),
	 * else workers could deadlock; so make workers a NOP.
	 */
	dev->flags = 0;
	del_timer_sync (&dev->delay);
	tasklet_kill (&dev->bh);
	DPRINTK("END of the function usbnet_stop\n");

	return 0;
}

/*-------------------------------------------------------------------------*/

// posts reads, and enables write queuing

// precondition: never called in_interrupt

static int usbnet_open (struct net_device *net)
{
	struct usbnet		*dev = netdev_priv(net);
	int			retval = 0;
	struct driver_info	*info = dev->driver_info;
	DPRINTK("START of the function usbnet_open\n");
	// put into "known safe" state
	if (info->reset && (retval = info->reset (dev)) < 0) {
		if (netif_msg_ifup (dev))
			devinfo (dev,
				"open reset fail (%d) usbnet usb-%s-%s, %s",
				retval,
				dev->udev->bus->bus_name, dev->udev->devpath,
			info->description);
		goto done;
	}

	// insist peer be connected
	if (info->check_connect && (retval = info->check_connect (dev)) < 0) {
		if (netif_msg_ifup (dev))
			devdbg (dev, "can't open; %d", retval);
		goto done;
	}

	/* start any status interrupt transfer */
	if (dev->interrupt) {
		retval = usb_submit_urb (dev->interrupt, GFP_KERNEL);
		if (retval < 0) {
			if (netif_msg_ifup (dev))
				deverr (dev, "intr submit %d", retval);
			goto done;
		}
	}

	netif_start_queue (net);
	if (netif_msg_ifup (dev)) {
		char	*framing;

			framing = "simple";

		devinfo (dev, "open: enable queueing "
				"(rx %d, tx %d) mtu %d %s framing",
			RX_QLEN (dev), TX_QLEN (dev), dev->net->mtu,
			framing);
	}

	// delay posting reads until we're fully open
	tasklet_schedule (&dev->bh);
done:
	DPRINTK("END of the function usbnet_open\n");
	return retval;
}

#ifdef check
static void usbnet_set_rx_mode (struct net_device *dev)
{
        struct usbnet *mcs = dev->priv;
	int status;
	__u8 ReadHifVal;	
        DPRINTK("%s: usbnet_set_rx_mode(%4.4x) done\n", dev->name, dev->flags);
        // Setting the board to IFF_ALLMULTI 

        if (dev->flags & IFF_ALLMULTI)
        {
			mcs->HifReg15 |= HIF_REG_15_ALLMULTICAST;
                        //enableMulticastBit(tp);

                DPRINTK("usbnet_set_rx_mode:%s: All Multicast mode enabled.\n",dev->name);
        }
        else
        {
			mcs->HifReg15 &= ~HIF_REG_15_ALLMULTICAST;
		
                        //disableMulticastBit(tp);

                DPRINTK("usbnet_set_rx_mode:%s: All Multicast mode disabled.\n",dev->name);
        }
        // Setting the board to IFF_PROMISC 
        if (dev->flags & IFF_PROMISC)
        {
			mcs->HifReg15 |= HIF_REG_15_PROMISCIOUS;
                        //enablePromiscousBit(tp);

                DPRINTK("usbnet_set_rx_mode %s: Promiscuous mode enabled.\n",dev->name);
        }
        else
        {
			mcs->HifReg15 &= ~HIF_REG_15_PROMISCIOUS;
                        //disablePromiscousBit(tp);

                DPRINTK("usbnet_set_rx_mode:%s: Promiscuous mode disabled.\n",dev->name);
        }

	status=0x0;
        status=SetVendorCommandPassive( mcs,HIF_REG_15,1,&mcs->HifReg15);
        DPRINTK("in usbnet_set_rx_mode  Writing mcs->HifReg15 is %04x \n",mcs->HifReg15 );
        if(status >=0)
        {
                DPRINTK("in usbnet_set_rx_mode  writing mcs->HifReg15 SUCCESS\n" );
                //break;
        }
        else
        {
                DPRINTK("in usbnet_set_rx_mode  writing mcs->HifReg15 FAILED\n");
                mcs7830_disconnect(mcs->udev, (void *) mcs);
        }
        status=0;
        status=GetVendorCommandPassive( mcs,HIF_REG_15,1,&ReadHifVal);
        DPRINTK("in usbnet_set_rx_mode  Read mcs->HifReg15 is %04x \n",ReadHifVal );




}
#endif



/*-------------------------------------------------------------------------*/

static void usbnet_get_drvinfo (struct net_device *net, struct ethtool_drvinfo *info)
{
	struct usbnet *dev = netdev_priv(net);

	strncpy (info->driver, driver_name, sizeof info->driver);
	strncpy (info->version, DRIVER_VERSION, sizeof info->version);
	strncpy (info->fw_version, dev->driver_info->description,
		sizeof info->fw_version);
	usb_make_path (dev->udev, info->bus_info, sizeof info->bus_info);
}

static u32 usbnet_get_link (struct net_device *net)
{
	struct usbnet *dev = netdev_priv(net);

	/* If a check_connect is defined, return it's results */
	if (dev->driver_info->check_connect)
		return dev->driver_info->check_connect (dev) == 0;

	/* Otherwise, we're up to avoid breaking scripts */
	return 1;
}

static u32 usbnet_get_msglevel (struct net_device *net)
{
	struct usbnet *dev = netdev_priv(net);

	return dev->msg_enable;
}

static void usbnet_set_msglevel (struct net_device *net, u32 level)
{
	struct usbnet *dev = netdev_priv(net);

	dev->msg_enable = level;
}

static int usbnet_ioctl (struct net_device *net, struct ifreq *rq, int cmd)
{
#ifdef NEED_MII
	{
	struct usbnet *dev = netdev_priv(net);


	#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,10)
	if (dev->mii.mdio_read != NULL && dev->mii.mdio_write != NULL)
         return generic_mii_ioctl(&dev->mii,
                                (struct mii_ioctl_data *) &rq->ifr_data,
                                cmd, NULL);

	#endif

	#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,10)
	if (dev->mii.mdio_read != NULL && dev->mii.mdio_write != NULL)
		return generic_mii_ioctl(&dev->mii, if_mii(rq), cmd, NULL);
	#endif
	}
#endif
	return -EOPNOTSUPP;
}

/*-------------------------------------------------------------------------*/

/* work that cannot be done in interrupt context uses keventd.
 *
 * NOTE:  with 2.5 we could do more of this using completion callbacks,
 * especially now that control transfers can be queued.
 */
static void
kevent (void *data)
{
	struct usbnet		*dev = data;
	int			status;

	/* usb_clear_halt() needs a thread context */
	if (test_bit (EVENT_TX_HALT, &dev->flags)) {
		unlink_urbs (dev, &dev->txq);
		status = usb_clear_halt (dev->udev, dev->out);
		if (status < 0 && status != -EPIPE) {
			if (netif_msg_tx_err (dev))
				deverr (dev, "can't clear tx halt, status %d",
					status);
		} else {
			clear_bit (EVENT_TX_HALT, &dev->flags);
			netif_wake_queue (dev->net);
		}
	}
	if (test_bit (EVENT_RX_HALT, &dev->flags)) {
		unlink_urbs (dev, &dev->rxq);
		status = usb_clear_halt (dev->udev, dev->in);
		if (status < 0 && status != -EPIPE) {
			if (netif_msg_rx_err (dev))
				deverr (dev, "can't clear rx halt, status %d",
					status);
		} else {
			clear_bit (EVENT_RX_HALT, &dev->flags);
			tasklet_schedule (&dev->bh);
		}
	}

	/* tasklet could resubmit itself forever if memory is tight */
	if (test_bit (EVENT_RX_MEMORY, &dev->flags)) {
		struct urb	*urb = NULL;

		if (netif_running (dev->net))
			urb = usb_alloc_urb (0, GFP_KERNEL);
		else
			clear_bit (EVENT_RX_MEMORY, &dev->flags);
		if (urb != NULL) {
			clear_bit (EVENT_RX_MEMORY, &dev->flags);
			rx_submit (dev, urb, GFP_KERNEL);
			tasklet_schedule (&dev->bh);
		}
	}

	if (test_bit (EVENT_LINK_RESET, &dev->flags)) {
		struct driver_info 	*info = dev->driver_info;
		int			retval = 0;

		clear_bit (EVENT_LINK_RESET, &dev->flags);
		if(info->link_reset && (retval = info->link_reset(dev)) < 0) {
			devinfo(dev, "link reset failed (%d) usbnet usb-%s-%s, %s",
				retval,
				dev->udev->bus->bus_name, dev->udev->devpath,
				info->description);
		}
	}

	if (dev->flags)
		devdbg (dev, "kevent done, flags = 0x%lx",
			dev->flags);
}

/*-------------------------------------------------------------------------*/
// Call back for zero length packet transfer
static void Zero_complete(struct urb *urb,struct pt_regs *regs)
{
		usb_free_urb (urb);
}
static void tx_complete (struct urb *urb, struct pt_regs *regs)
{
	struct sk_buff		*skb = (struct sk_buff *) urb->context;
	struct skb_data		*entry = (struct skb_data *) skb->cb;
	struct usbnet		*dev = entry->dev;
	//DPRINTK("in the function tx_complete start \n");
	if (urb->status == 0) {
		dev->stats.tx_packets++;
		dev->stats.tx_bytes += entry->length;
	} else {
		dev->stats.tx_errors++;

		switch (urb->status) {
		case -EPIPE:
			defer_kevent (dev, EVENT_TX_HALT);
			break;

		/* software-driven interface shutdown */
		case -ECONNRESET:		// async unlink
		case -ESHUTDOWN:		// hardware gone
			break;

		// like rx, tx gets controller i/o faults during khubd delays
		// and so it uses the same throttling mechanism.
		case -EPROTO:		// ehci
		case -ETIMEDOUT:	// ohci
		case -EILSEQ:		// uhci
			if (!timer_pending (&dev->delay)) {
				mod_timer (&dev->delay,
					jiffies + THROTTLE_JIFFIES);
				if (netif_msg_link (dev))
					devdbg (dev, "tx throttle %d",
							urb->status);
			}
	DPRINTK("netif_stop_queue in the function tx_complete at -EILSEQ\n");
			netif_stop_queue (dev->net);
			break;
		default:
			if (netif_msg_tx_err (dev))
				devdbg (dev, "tx err %d", entry->urb->status);
			break;
		}
	}

	urb->dev = NULL;
	entry->state = tx_done;
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,14)
	defer_bh (dev, skb);
	#else
	defer_bh (dev, skb,&dev->txq);
	#endif
}

/*-------------------------------------------------------------------------*/

static void usbnet_tx_timeout (struct net_device *net)
{
	struct usbnet		*dev = netdev_priv(net);

	unlink_urbs (dev, &dev->txq);
	tasklet_schedule (&dev->bh);

	// FIXME: device recovery -- reset?
}

/*-------------------------------------------------------------------------*/

static int usbnet_start_xmit (struct sk_buff *skb, struct net_device *net)
{
	struct usbnet		*dev = netdev_priv(net);
	int			length;
	int			retval = NET_XMIT_SUCCESS;
	struct urb		*urb = NULL,*Zerourb=NULL;
	struct skb_data		*entry;
	struct driver_info	*info = dev->driver_info;
	unsigned long		flags;
	int NeedtoSendZero=0,retval2;//added for handling 
						 //max size packets for USB
	

	//DPRINTK(" in usbnet_start_xmit Start\n");
	// some devices want funky USB-level framing, for
	// win32 driver (usually) and/or hardware quirks
	if (info->tx_fixup) {
		skb = info->tx_fixup (dev, skb, GFP_ATOMIC);
		if (!skb) {
			if (netif_msg_tx_err (dev))
				devdbg (dev, "can't tx_fixup skb");
			goto drop;
		}
	}
	length = skb->len;

	if (!(urb = usb_alloc_urb (0, GFP_ATOMIC))) {
		if (netif_msg_tx_err (dev))
			devdbg (dev, "no urb");
		goto drop;
	}

	entry = (struct skb_data *) skb->cb;
	entry->urb = urb;
	entry->dev = dev;
	entry->state = tx_start;
	entry->length = length;

	// FIXME: reorganize a bit, so that fixup() fills out NetChip
	// framing too. (Packet ID update needs the spinlock...)
	// [ BETTER:  we already own net->xmit_lock, that's enough ]


	usb_fill_bulk_urb (urb, dev->udev, dev->out,
			skb->data, skb->len, tx_complete, skb);
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,14)
	urb->transfer_flags |= URB_ASYNC_UNLINK;
	#endif

	/* don't assume the hardware handles USB_ZERO_PACKET
	 * NOTE:  strictly conforming cdc-ether devices should expect
	 * the ZLP here, but ignore the one-byte packet.
	 *
	 * FIXME zero that byte, if it doesn't require a new skb.
	 */
	if ((length % dev->maxpacket) == 0){
		NeedtoSendZero=1;//added by 
		urb->transfer_buffer_length++;
	}

	spin_lock_irqsave (&dev->txq.lock, flags);


	switch ((retval = usb_submit_urb (urb, GFP_ATOMIC))) {
	case -EPIPE:
	DPRINTK("netif_stop_queue in the function usbnet_start_xmit at EPIPE\n");
		netif_stop_queue (net);
		defer_kevent (dev, EVENT_TX_HALT);
		break;
	default:
		if (netif_msg_tx_err (dev))
			devdbg (dev, "tx: submit urb err %d", retval);
		break;
	case 0:
		net->trans_start = jiffies;
		__skb_queue_tail (&dev->txq, skb);
		if (dev->txq.qlen >= TX_QLEN (dev)){
		
	DPRINTK("netif_stop_queue in the function usbnet_start_xmit at case0\n");
			netif_stop_queue (net);
		}
	}
	spin_unlock_irqrestore (&dev->txq.lock, flags);

	if(NeedtoSendZero ==1)
	{	
		
		if (!(Zerourb = usb_alloc_urb (0, GFP_ATOMIC))) {
			if (netif_msg_tx_err (dev))
				devdbg (dev, "no urb");
			goto drop;
		}
		usb_fill_bulk_urb (Zerourb, dev->udev, dev->out,\
				skb->data, 0,Zero_complete, NULL);
		#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,14)
		Zerourb->transfer_flags |= URB_ASYNC_UNLINK;
		#endif

		retval2 = usb_submit_urb (urb, GFP_ATOMIC); 
		if(retval2 !=0)
		DPRINTK("Error sending Zero Length packet in transmission\n");

	}
	

	if (retval) {
		if (netif_msg_tx_err (dev))
			devdbg (dev, "drop, code %d", retval);
drop:
		retval = NET_XMIT_SUCCESS;
		dev->stats.tx_dropped++;
		if (skb)
			dev_kfree_skb_any (skb);
		usb_free_urb (urb);
	} else if (netif_msg_tx_queued (dev)) {
		devdbg (dev, "> tx, len %d, type 0x%x",
			length, skb->protocol);
	}
	return retval;
}


/*-------------------------------------------------------------------------*/

// tasklet (work deferred from completions, in_irq) or timer

static void usbnet_bh (unsigned long param)
{
	struct usbnet		*dev = (struct usbnet *) param;
	struct sk_buff		*skb;
	struct skb_data		*entry;

	while ((skb = skb_dequeue (&dev->done))) {
		entry = (struct skb_data *) skb->cb;
		switch (entry->state) {
		    case rx_done:
			entry->state = rx_cleanup;
			rx_process (dev, skb);
			continue;
		    case tx_done:
		    case rx_cleanup:
			usb_free_urb (entry->urb);
			dev_kfree_skb (skb);
			continue;
		    default:
			devdbg (dev, "bogus skb state %d", entry->state);
		}
	}

	// waiting for all pending urbs to complete?
	if (dev->wait) {
		if ((dev->txq.qlen + dev->rxq.qlen + dev->done.qlen) == 0) {
			wake_up (dev->wait);
		}

	// or are we maybe short a few urbs?
	} else if (netif_running (dev->net)
			&& netif_device_present (dev->net)
			&& !timer_pending (&dev->delay)
			&& !test_bit (EVENT_RX_HALT, &dev->flags)) {
		int	temp = dev->rxq.qlen;
		int	qlen = RX_QLEN (dev);

		if (temp < qlen) {
			struct urb	*urb;
			int		i;

			// don't refill the queue all at once
			for (i = 0; i < 10 && dev->rxq.qlen < qlen; i++) {
				urb = usb_alloc_urb (0, GFP_ATOMIC);
				if (urb != NULL)
					rx_submit (dev, urb, GFP_ATOMIC);
			}
			if (temp != dev->rxq.qlen && netif_msg_link (dev))
				devdbg (dev, "rxqlen %d --> %d",
						temp, dev->rxq.qlen);
			if (dev->rxq.qlen < qlen)
				tasklet_schedule (&dev->bh);
		}
		if (dev->txq.qlen < TX_QLEN (dev))
			netif_wake_queue (dev->net);
	}
}



/*-------------------------------------------------------------------------
 *
 * USB Device Driver support
 *
 *-------------------------------------------------------------------------*/
 
// precondition: never called in_interrupt

static void usbnet_disconnect (struct usb_interface *intf)
{
	struct usbnet		*dev;
	struct usb_device	*xdev;
	struct net_device	*net;

	dev = usb_get_intfdata(intf);
	usb_set_intfdata(intf, NULL);
	if (!dev)
		return;

	xdev = interface_to_usbdev (intf);

	if (netif_msg_probe (dev))
		devinfo (dev, "unregister usbnet usb-%s-%s, %s",
			xdev->bus->bus_name, xdev->devpath,
			dev->driver_info->description);
	
	net = dev->net;
	unregister_netdev (net);

	/* we don't hold rtnl here ... */
	flush_scheduled_work ();

	if (dev->driver_info->unbind)
		dev->driver_info->unbind (dev, intf);

	free_netdev(net);
	usb_put_dev (xdev);
}


/*-------------------------------------------------------------------------*/

static struct ethtool_ops usbnet_ethtool_ops;

// precondition: never called in_interrupt

static int
usbnet_probe (struct usb_interface *udev, const struct usb_device_id *prod)
{
	struct usbnet			*dev;
	struct net_device 		*net;
	struct usb_host_interface	*interface;
	struct driver_info		*info;
	struct usb_device		*xdev;
	int				status;
	int                             i;
	info = (struct driver_info *) prod->driver_info;
	if (!info) {
		dev_dbg (&udev->dev, "blacklisted by %s\n", driver_name);
		return -ENODEV;
	}
	xdev = interface_to_usbdev (udev);
	interface = udev->cur_altsetting;

	usb_get_dev (xdev);

	status = -ENOMEM;

	// set up our own records
	net = alloc_etherdev(sizeof(*dev));
	if (!net) {
		dbg ("can't kmalloc dev");
		goto out;
	}

	dev = netdev_priv(net);
	dev->udev = xdev;
	dev->driver_info = info;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,10)
	dev->msg_enable = netif_msg_init (msg_level, NETIF_MSG_DRV
				| NETIF_MSG_PROBE | NETIF_MSG_LINK);
#endif

#ifdef CONFIG_USB_MOSCHIP
//        if(udev->descriptor.idVendor == 0x9710 &&  udev->descriptor.idProduct == 0x7830 )

	if((dev)->udev->speed == USB_SPEED_HIGH) DPRINTK("device is USB2.0\n"); 
	else
	DPRINTK("device is USB1.1\n");
        {
        usb_get_dev (xdev);

        DPRINTK(" USB device MCS7830 device is attached \n");
        }
        status=0;
        status=ANGInitializeDev(dev);
        if(status >=0)
        DPRINTK("Device initialization is comepleted\n");
        else
        {
                DPRINTK("ERROR: device initialization  FAILURE (%x)\n", status);
                mcs7830_disconnect(dev->udev, (void *) dev);
                return -1;//NULL;
        }

#endif




	skb_queue_head_init (&dev->rxq);
	skb_queue_head_init (&dev->txq);
	skb_queue_head_init (&dev->done);
	dev->bh.func = usbnet_bh;
	dev->bh.data = (unsigned long) dev;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,20)
	INIT_WORK (&dev->kevent, kevent);
#else
	INIT_WORK (&dev->kevent, kevent, dev);
#endif
	dev->delay.function = usbnet_bh;
	dev->delay.data = (unsigned long) dev;
	init_timer (&dev->delay);

//	SET_MODULE_OWNER (net);
	dev->net = net;
	strcpy (net->name, "eth%d");//usb%d");
	memcpy (net->dev_addr, node_id, sizeof node_id);
	for (i = 0; i < 6; i++) // Hardware Address
        {
                net->dev_addr[i] = dev->AiPermanentNodeAddress[i];
                net->broadcast[i] = 0xff;
        } 



	net->change_mtu = usbnet_change_mtu;
	net->get_stats = usbnet_get_stats;
	net->hard_start_xmit = usbnet_start_xmit;
	net->open = usbnet_open;
	net->stop = usbnet_stop;
	net->watchdog_timeo = TX_TIMEOUT_JIFFIES;
	net->tx_timeout = usbnet_tx_timeout;
	net->do_ioctl = usbnet_ioctl;
	net->ethtool_ops = &usbnet_ethtool_ops;
//	net->set_multicast_list = usbnet_set_rx_mode;

	dev->mii.dev = net;
        dev->mii.mdio_read = mdio_read;
        dev->mii.mdio_write = mdio_write;
	dev->mii.phy_id_mask = 0x3f;
        dev->mii.reg_num_mask = 0x1f;
	dev->mii.phy_id = *((u8 *)dev->AiPermanentNodeAddress + 1);


	// allow device-specific bind/init procedures
	// NOTE net->name still not usable ...
	if (info->bind) {
		status = info->bind (dev, udev);
		// heuristic:  "usb%d" for links we know are two-host,
		// else "eth%d" when there's reasonable doubt.  userspace
		// can rename the link if it knows better.
		if ((dev->driver_info->flags & FLAG_ETHER) != 0
				&& (net->dev_addr [0] & 0x02) == 0)
			strcpy (net->name, "eth%d");//usb%d");
	} else if (!info->in || info->out)
		status = get_endpoints (dev, udev);
	else {
		dev->in = usb_rcvbulkpipe (xdev, info->in);
		dev->out = usb_sndbulkpipe (xdev, info->out);
		if (!(info->flags & FLAG_NO_SETINT))
			status = usb_set_interface (xdev,
				interface->desc.bInterfaceNumber,
				interface->desc.bAlternateSetting);
		else
			status = 0;

	}

	if (status == 0 && dev->status)
		status = init_status (dev, udev);
	if (status < 0)
		goto out1;

	dev->maxpacket = usb_maxpacket (dev->udev, dev->out, 1);
	
	SET_NETDEV_DEV(net, &udev->dev);
	status = register_netdev (net);
	if (status)
		goto out3;
	if (netif_msg_probe (dev))
		devinfo (dev, "register usbnet at usb-%s-%s, %s, "
				"%02x:%02x:%02x:%02x:%02x:%02x",
			xdev->bus->bus_name, xdev->devpath,
			dev->driver_info->description,
			net->dev_addr [0], net->dev_addr [1],
			net->dev_addr [2], net->dev_addr [3],
			net->dev_addr [4], net->dev_addr [5]);

	// ok, it's ready to go.
	usb_set_intfdata (udev, dev);

	// start as if the link is up
	netif_device_attach (net);

	return 0;

out3:
	if (info->unbind)
		info->unbind (dev, udev);
out1:
	free_netdev(net);
out:
	usb_put_dev(xdev);
	return status;
}





/*-------------------------------------------------------------------------*/

#ifdef	CONFIG_PM

#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,10)
static int usbnet_suspend (struct usb_interface *intf, pm_message_t message)
{
	struct usbnet		*dev = usb_get_intfdata(intf);
	
	/* accelerate emptying of the rx and queues, to avoid
	 * having everything error out.
	 */
	netif_device_detach (dev->net);
	(void) unlink_urbs (dev, &dev->rxq);
	(void) unlink_urbs (dev, &dev->txq);
	intf->dev.power.power_state = PMSG_SUSPEND;
	return 0;
}

static int usbnet_resume (struct usb_interface *intf)
{
	struct usbnet		*dev = usb_get_intfdata(intf);

	intf->dev.power.power_state = PMSG_ON;
	netif_device_attach (dev->net);
	tasklet_schedule (&dev->bh);
	return 0;
}
#endif
#else	/* !CONFIG_PM */

#define	usbnet_suspend	NULL
#define	usbnet_resume	NULL

#endif	/* CONFIG_PM */

/*-------------------------------------------------------------------------*/


/*
 * chip vendor names won't normally be on the cables, and
 * may not be on the device.
 */

static const struct usb_device_id	products [] = {

#ifdef  CONFIG_USB_MOSCHIP
{
        USB_DEVICE (MCS_VENDOR_ID,MCS_PRODUCT_ID_7830),      //MOSCHIP7830
        .driver_info =  (unsigned long) &moschip_info,
},
{
        USB_DEVICE (MCS_VENDOR_ID,MCS_PRODUCT_ID_7832),      //MOSCHIP7832
        .driver_info =  (unsigned long) &moschip_info,
},
#endif
	{ },		// END
};
MODULE_DEVICE_TABLE (usb, products);

static struct usb_driver usbnet_driver = {
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2,6,15)
	.owner =	THIS_MODULE,
	#endif
	.name =		driver_name,
	.id_table =	products,
	.probe =	usbnet_probe,
	.disconnect =	usbnet_disconnect,
	#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,10)
	.suspend =	usbnet_suspend,
	.resume =	usbnet_resume,
	#endif
};

/* Default ethtool_ops assigned.  Devices can override in their bind() routine */
static struct ethtool_ops usbnet_ethtool_ops = {
	.get_drvinfo		= usbnet_get_drvinfo,
	.get_link		= usbnet_get_link,
	.get_msglevel		= usbnet_get_msglevel,
	.set_msglevel		= usbnet_set_msglevel,
};

/*-------------------------------------------------------------------------*/

static int __init usbnet_init (void)
{
	// compiler should optimize these out
	BUG_ON (sizeof (((struct sk_buff *)0)->cb)
			< sizeof (struct skb_data));

	random_ether_addr(node_id);

 	return usb_register(&usbnet_driver);
}
module_init (usbnet_init);

static void __exit usbnet_exit (void)
{
 	usb_deregister (&usbnet_driver);
}
module_exit (usbnet_exit);
MODULE_DESCRIPTION ("USB to network adapter MCS7830)");
MODULE_LICENSE ("GPL");
