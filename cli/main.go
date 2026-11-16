package main

import (
	"embed"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

//go:embed dist
var webAssets embed.FS

func main() {
	args := os.Args[1:]
	if len(args) > 0 {
		switch args[0] {
		case "-h", "--help", "help":
			fmt.Print(usage)
			return
		case "serve":
			args = args[1:]
		default:
			if !strings.HasPrefix(args[0], "-") {
				if err := runDocument(args[0], args[1:], os.Stdin, os.Stdout); err != nil {
					fmt.Fprintln(os.Stderr, err)
					os.Exit(1)
				}
				return
			}
		}
	}
	options := flag.NewFlagSet("serve", flag.ExitOnError)
	address := options.String("listen", "127.0.0.1:8080", "HTTP listen address")
	options.Usage = func() { fmt.Fprint(options.Output(), usage) }
	_ = options.Parse(args)
	if options.NArg() != 0 {
		log.Fatal("unexpected server argument; use --help")
	}

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
