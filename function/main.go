package function

import (
	"context"
	"fmt"
	"image"
	"image/jpeg"
	"log"
	"os"
	"path/filepath"
	"strings"

	"cloud.google.com/go/storage"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"github.com/googleapis/google-cloudevents-go/cloud/storagedata"
	"golang.org/x/image/webp"
	"google.golang.org/protobuf/encoding/protojson"
)

func init() {
	functions.CloudEvent("CloudEventFunc", CloudEventFunc)
}

func CloudEventFunc(ctx context.Context, e cloudevents.Event) error {
	log.Printf("Event ID: %s", e.ID())
	log.Printf("Event Type: %s", e.Type())

	var data storagedata.StorageObjectData
	if err := protojson.Unmarshal(e.Data(), &data); err != nil {
		return fmt.Errorf("protojson.Unmarshal: %w", err)
	}

	log.Printf("Bucket: %s", data.GetBucket())
	log.Printf("File: %s", data.GetName())
	log.Printf("Metageneration: %d", data.GetMetageneration())
	log.Printf("Created: %s", data.GetTimeCreated().AsTime())
	log.Printf("Updated: %s", data.GetUpdated().AsTime())

	srcBucket := data.GetBucket()
	srcKey := data.GetName()

	dstBucket := os.Getenv("DESTINATION_BUCKET")
	dstKey := trimExtension(srcKey) + ".jpeg"

	img, err := downloadImage(ctx, srcBucket, srcKey)
	if err != nil {
		return err
	}

	if err := uploadImage(ctx, dstBucket, dstKey, img); err != nil {
		return err
	}

	return nil
}

func downloadImage(ctx context.Context, bucket, key string) (image.Image, error) {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to init Cloud Storage client: %w", err)
	}
	reader, err := client.Bucket(bucket).Object(key).NewReader(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get reader: %w", err)
	}
	defer reader.Close()
	img, err := webp.Decode(reader)
	if err != nil {
		return nil, fmt.Errorf("failed to decode webp: %w", err)
	}
	return img, nil
}

func uploadImage(ctx context.Context, bucket, key string, img image.Image) error {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return fmt.Errorf("failed to init Cloud Storage client: %w", err)
	}
	writer := client.Bucket(bucket).Object(key).NewWriter(ctx)
	if err != nil {
		return fmt.Errorf("failed to get writer: %w", err)
	}
	defer writer.Close()
	if err := jpeg.Encode(writer, img, &jpeg.Options{Quality: 100}); err != nil {
		return fmt.Errorf("failed to encode jpeg: %w", err)
	}
	return nil
}

func trimExtension(fileName string) string {
	return strings.TrimSuffix(fileName, filepath.Ext(fileName))
}
