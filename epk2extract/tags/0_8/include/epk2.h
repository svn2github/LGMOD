/*
 * epk2.h
 *
 *  Created on: 16.02.2011
 *      Author: sirius
 */

#ifndef EPK2_H_
#define EPK2_H_

#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/err.h>
#include <openssl/aes.h>
#include <epk.h>

typedef int bool;
#define TRUE   (1)
#define FALSE  (0)

enum {
	MAX_PAK_CHUNKS = 0x10
};
enum {
	SIGNATURE_SIZE = 0x80
};

struct epk2_header_t {
	unsigned char _00_signature[SIGNATURE_SIZE];
	unsigned char _01_epak_magic[4];
	uint32_t _02_file_size;
	uint32_t _03_pak_count;
	unsigned char _04_fw_format[4];
	unsigned char _05_fw_version[4];
	unsigned char _06_fw_type[32];
	uint32_t _07_header_length;
	uint32_t _08_unknown;
};

struct pak2_header_t {
	unsigned char _01_type_code[4];
	uint32_t _02_unknown1;
	uint32_t _03_unknown2;
	uint32_t _04_next_pak_file_offset;
	uint32_t _05_next_pak_length;
};

struct pak2_chunk_header_t {
	unsigned char _00_signature[SIGNATURE_SIZE];
	unsigned char _01_type_code[4];
	unsigned char _02_unknown1[4];
	unsigned char _03_platform[15];
	unsigned char _04_unknown3[105];
};

struct pak2_chunk_t {
	struct pak2_chunk_header_t *header;
	unsigned char *content;
	int content_len;
};

struct pak2_t {
	pak_type_t type;
	struct pak2_header_t *header;
	unsigned int chunk_count;
	struct pak2_chunk_t **chunks;
};


#endif /* EPK2_H_ */
