package main

import (
	"embed"
	"flag"
	"io/fs"
	"log"
	"net"
	"net/http"
	"time"
)

//go:embed dist
var webAssets embed.FS

func main() {
	address := flag.String("listen", "127.0.0.1:8080", "HTTP listen address")
	flag.Parse()

	files, err := fs.Sub(webAssets, "dist")
	if err != nil {
		log.Fatal(err)
	}
	listener, err := net.Listen("tcp", *address)
	if err != nil {
		log.Fatal(err)
	}

	server := &http.Server{
		Handler:           http.FileServerFS(files),
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("MandalaThink web reader at http://%s", listener.Addr())
	log.Fatal(server.Serve(listener))
}
