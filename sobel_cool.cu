/* Example sobel code for ECE574 -- Spring 2023 */
/* By Vince Weaver <vincent.weaver@maine.edu> */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <math.h>

#include <jpeglib.h>

#include <cuda.h>

#include <papi.h>

/* Filters */
static int sobel_x_filter[9]={ -1, 0,+1  ,-2, 0,+2  ,-1, 0,+1};
static int sobel_y_filter[9]={ -1,-2,-1  , 0, 0, 0  , 1, 2,+1};

/* Structure describing the image */
struct image_t {
	int xsize;
	int ysize;
	int depth;	/* bytes */
	unsigned char *pixels;
};

#if 0
__global__
void cuda_generic_convolve (int n, char *in, char *out, int *matrix) {

}

__global__
void cuda_combine (int n, unsigned char *sobel_x,
		unsigned char *sobel_y, unsigned char *output) {
}

#endif


/* very inefficient convolve code */
static void *generic_convolve(struct image_t *input,
				struct image_t *output,
				int *filter) {

	int x,y,k,l,d;
	uint32_t color;
	int sum,depth,width;

	int ystart, yend;

	ystart=0;
	yend=input->ysize;

	depth=input->depth;
	width=input->xsize * input->depth;

	if (ystart==0) ystart=1;
	if (yend==input->ysize) yend=input->ysize-1;

	for(d=0;d<3;d++) {
	   for(x=1;x<input->xsize-1;x++) {
	     for(y=ystart;y<yend;y++) {
		sum=0;
		for(k=-1;k<2;k++) {
		   for(l=-1;l<2;l++) {
			color=input->pixels[((y+l)*width)+(x*depth+d+k*depth)];
			sum+=color * filter[(l+1)*3+(k+1)];
		   }
		}

		if (sum<0) sum=0;
		if (sum>255) sum=255;

		output->pixels[(y*width)+x*depth+d]=sum;
	     }
	   }
	}

	return NULL;
}

static int combine(struct image_t *sobel_x,
			struct image_t *sobel_y,
			struct image_t *output) {
	int i;
	int out;

	for(i=0;i<( sobel_x->depth * sobel_x->xsize * sobel_x->ysize );i++) {

		out=sqrt(
			(sobel_x->pixels[i]*sobel_x->pixels[i])+
			(sobel_y->pixels[i]*sobel_y->pixels[i])
			);
		if (out>255) out=255;
		if (out<0) out=0;
		output->pixels[i]=out;
	}

	return 0;
}

static int load_jpeg(char *filename, struct image_t *image) {

	FILE *fff;
	struct jpeg_decompress_struct cinfo;
	struct jpeg_error_mgr jerr;
	JSAMPROW output_data;
	unsigned int scanline_len;
	int scanline_count=0;

	fff=fopen(filename,"rb");
	if (fff==NULL) {
		fprintf(stderr, "Could not load %s: %s\n",
			filename, strerror(errno));
		return -1;
	}

	/* set up jpeg error routines */
	cinfo.err = jpeg_std_error(&jerr);

	/* Initialize cinfo */
	jpeg_create_decompress(&cinfo);

	/* Set input file */
	jpeg_stdio_src(&cinfo, fff);

	/* read header */
	jpeg_read_header(&cinfo, TRUE);

	/* Start decompressor */
	jpeg_start_decompress(&cinfo);

	printf("output_width=%d, output_height=%d, output_components=%d\n",
		cinfo.output_width,
		cinfo.output_height,
		cinfo.output_components);

	image->xsize=cinfo.output_width;
	image->ysize=cinfo.output_height;
	image->depth=cinfo.output_components;

	scanline_len = cinfo.output_width * cinfo.output_components;
	image->pixels=(unsigned char *)malloc(cinfo.output_width * cinfo.output_height * cinfo.output_components);

	while (scanline_count < cinfo.output_height) {
		output_data = (image->pixels + (scanline_count * scanline_len));
		jpeg_read_scanlines(&cinfo, &output_data, 1);
		scanline_count++;
	}

	/* Finish decompressing */
	jpeg_finish_decompress(&cinfo);

	jpeg_destroy_decompress(&cinfo);

	fclose(fff);

	return 0;
}

static int store_jpeg(const char *filename, struct image_t *image) {

	struct jpeg_compress_struct cinfo;
	struct jpeg_error_mgr jerr;
	int quality=90; /* % */
	int i;

	FILE *fff;

	JSAMPROW row_pointer[1];
	int row_stride;

	/* setup error handler */
	cinfo.err = jpeg_std_error(&jerr);

	/* initialize jpeg compression object */
	jpeg_create_compress(&cinfo);

	/* Open file */
	fff = fopen(filename, "wb");
	if (fff==NULL) {
		fprintf(stderr, "can't open %s: %s\n",
			filename,strerror(errno));
		return -1;
	}

	jpeg_stdio_dest(&cinfo, fff);

	/* Set compression parameters */
	cinfo.image_width = image->xsize;
	cinfo.image_height = image->ysize;
	cinfo.input_components = image->depth;
	cinfo.in_color_space = JCS_RGB;
	jpeg_set_defaults(&cinfo);
	jpeg_set_quality(&cinfo, quality, TRUE);

	/* start compressing */
	jpeg_start_compress(&cinfo, TRUE);

	row_stride=image->xsize*image->depth;

	for(i=0;i<image->ysize;i++) {
		row_pointer[0] = & image->pixels[i * row_stride];
		jpeg_write_scanlines(&cinfo, row_pointer, 1);
	}

	/* finish compressing */
	jpeg_finish_compress(&cinfo);

	/* close file */
	fclose(fff);

	/* clean up */
	jpeg_destroy_compress(&cinfo);

	return 0;
}

int main(int argc, char **argv) {

	struct image_t image,sobel_x,sobel_y,new_image;
	long long start_time,load_time;
	long long combine_after=0,combine_before=0;
	long long convolve_after=0,convolve_before=0;
	long long copy_before=0,copy_after=0,copy2_before=0,copy2_after=0;
	long long store_after,store_before;

	/* Check command line usage */
	if (argc<2) {
		fprintf(stderr,"Usage: %s image_file\n",argv[0]);
		return -1;
	}

	PAPI_library_init(PAPI_VER_CURRENT);

	start_time=PAPI_get_real_usec();

	/* Load an image */
	load_jpeg(argv[1],&image);

	load_time=PAPI_get_real_usec();

	/* Allocate space for output image */
	new_image.xsize=image.xsize;
	new_image.ysize=image.ysize;
	new_image.depth=image.depth;
	new_image.pixels=
		(unsigned char *)calloc(image.xsize*image.ysize*image.depth,
					sizeof(char));

	/* Allocate space for output image */
	sobel_x.xsize=image.xsize;
	sobel_x.ysize=image.ysize;
	sobel_x.depth=image.depth;
	sobel_x.pixels=
		(unsigned char *)calloc(image.xsize*image.ysize*image.depth,
					sizeof(char));

	/* Allocate space for output image */
	sobel_y.xsize=image.xsize;
	sobel_y.ysize=image.ysize;
	sobel_y.depth=image.depth;
	sobel_y.pixels=
		(unsigned char *)calloc(image.xsize*image.ysize*image.depth,
					sizeof(char));

	convolve_before=PAPI_get_real_usec();

	/* sobel x convolution */
	generic_convolve(&image,&sobel_x,sobel_x_filter);

	/* sobel y convolution */
	generic_convolve(&image,&sobel_y,sobel_y_filter);

	convolve_after=PAPI_get_real_usec();

	/* Combine to form output */

	combine_before=PAPI_get_real_usec();

	combine(&sobel_x,&sobel_y,&new_image);

	/* REPLACE THE ABOVE WITH YOUR CODE */
	/* IT SHOULD ALLOCATE SPACE ON DEVICE */
	/* COPY SOBEL_X and SOBEL_Y data to device */
	/* RUN THE KERNEL */
	/* THEN COPY THE RESULTS BACK */

	combine_after=PAPI_get_real_usec();

	store_before=PAPI_get_real_usec();

	/* Write data back out to disk */
	store_jpeg("out.jpg",&new_image);

	store_after=PAPI_get_real_usec();

	/* Print timing results */
	printf("Load time: %lld\n",load_time-start_time);
        printf("Convolve time: %lld\n",convolve_after-convolve_before);
	printf("Copy host to device: %lld\n",(copy_after-copy_before));
        printf("Combine time: %lld\n",combine_after-combine_before);
	printf("Copy device to host: %lld\n",(copy2_after-copy2_before));
        printf("Store time: %lld\n",store_after-store_before);
	printf("Total time = %lld\n",store_after-start_time);

	return 0;
}
