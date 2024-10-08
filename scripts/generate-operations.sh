#!/bin/bash -e

if [ $# -eq 0 ]; then
  echo "Please provide a path to the S3 module and pipe the output to a file. Example:"
  echo
  echo "$0 ~/go/pkg/mod/github.com/aws/aws-sdk-go-v2/service/s3@v1.61.2 > operations.go"
  echo
  exit 1
fi

cat <<EOS
package s3autoregion

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/service/s3"
)
EOS


find "$1" -type f -name 'api_op_*' -maxdepth 1 | sort | while read path
do
  op=$(basename "$path" .go | cut -d '_' -f 3)
  if [[ "$op" == "ListBuckets" || "$op" == "ListDirectoryBuckets" || "$op" == "WriteGetObjectResponse" ]]; then
    cat <<EOS

func (c *Client) ${op}(ctx context.Context, params *s3.${op}Input, optFns ...func(*s3.Options)) (*s3.${op}Output, error) {
	return c.client.${op}(ctx, params, optFns...)
}
EOS
  elif [[ "$op" == "CreateBucket" ]]; then
    cat <<EOS

func (c *Client) ${op}(ctx context.Context, params *s3.${op}Input, optFns ...func(*s3.Options)) (*s3.${op}Output, error) {
	result, err := c.client.${op}(ctx, params, optFns...)
	if err == nil {
		if params.${op}Configuration == nil {
			c.setBucketRegion(params.Bucket, "us-east-1")
		} else {
			c.setBucketRegion(params.Bucket, string(params.${op}Configuration.LocationConstraint))
		}
	}
	return result, err
}
EOS
  elif [[ "$op" == "CreateSession" ]]; then
    cat <<EOS

func (c *Client) ${op}(ctx context.Context, params *s3.${op}Input, optFns ...func(*s3.Options)) (*s3.${op}Output, error) {
	region := c.getBucketRegion(params.Bucket)
	return c.client.${op}(ctx, params, append(optFns, setRegionFn(region))...)
}
EOS
  elif [[ "$op" == "GetBucketLocation" ]]; then
    cat <<EOS

func (c *Client) ${op}(ctx context.Context, params *s3.${op}Input, optFns ...func(*s3.Options)) (*s3.${op}Output, error) {
	result, err := c.client.${op}(ctx, params, optFns...)
	if err == nil {
		c.setBucketRegion(params.Bucket, string(result.LocationConstraint))
	}
	return result, err
}
EOS
  else
    cat <<EOS

func (c *Client) ${op}(ctx context.Context, params *s3.${op}Input, optFns ...func(*s3.Options)) (*s3.${op}Output, error) {
	region := c.getBucketRegion(params.Bucket)
	result, err := c.client.${op}(ctx, params, append(optFns, setRegionFn(region))...)
	if newRegion, ok := c.followXAmzBucketRegion(params.Bucket, region, err); ok {
		result, err = c.client.${op}(ctx, params, append(optFns, setRegionFn(newRegion))...)
	}
	return result, err
}
EOS
  fi
done
