package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/shirou/gopsutil/process"
)

type ProcessInfo struct {
	PID  int32  `json:"pid"`
	Name string `json:"name"`
}

type ForensicsCheck struct {
	IsRunning bool   `json:"is_running"`
	ToolName  string `json:"tool_name"`
}

var forensicsTools = []string{
	"FTK Imager",
	"Autopsy",
	"EnCase",
	"X-Ways Forensics",
}

func main() {

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	fmt.Println("Press Ctrl+C to stop the program.")
	fmt.Println("Writing process data to 'processes.json'.")
	fmt.Println("Writing forensics tool check results to 'forensics_check.json'.\n")

	for {
		select {
		case <-stop:
			fmt.Println("\nGoodbye!")
			return
		default:
			err := writeProcessesToJSON("processes.json")
			if err != nil {
				log.Printf("Error writing processes to JSON: %v\n", err)
			}

			err = checkForensicsTools("forensics_check.json")
			if err != nil {
				log.Printf("Error checking forensics tools: %v\n", err)
			}

			time.Sleep(2 * time.Second)
		}
	}
}

func writeProcessesToJSON(filename string) error {
	processes, err := process.Processes()
	if err != nil {
		return fmt.Errorf("error fetching processes: %v", err)
	}

	var processList []ProcessInfo

	for _, proc := range processes {
		name, err := proc.Name()
		if err != nil {
			name = "Unknown"
		}

		processList = append(processList, ProcessInfo{
			PID:  proc.Pid,
			Name: name,
		})
	}

	data, err := json.MarshalIndent(processList, "", "  ")
	if err != nil {
		return fmt.Errorf("error marshaling processes to JSON: %v", err)
	}

	err = os.WriteFile(filename, data, 0644)
	if err != nil {
		return fmt.Errorf("error writing JSON to file: %v", err)
	}

	return nil
}

func checkForensicsTools(filename string) error {
	processes, err := process.Processes()
	if err != nil {
		return fmt.Errorf("error fetching processes: %v", err)
	}

	forensicsStatus := make([]ForensicsCheck, 0)

	for _, tool := range forensicsTools {
		isRunning := false

		for _, proc := range processes {
			name, err := proc.Name()
			if err != nil {
				continue
			}

			if strings.Contains(strings.ToLower(name), strings.ToLower(tool)) {
				isRunning = true
				break
			}
		}

		forensicsStatus = append(forensicsStatus, ForensicsCheck{
			IsRunning: isRunning,
			ToolName:  tool,
		})
	}

	data, err := json.MarshalIndent(forensicsStatus, "", "  ")
	if err != nil {
		return fmt.Errorf("error marshaling forensics status to JSON: %v", err)
	}

	err = os.WriteFile(filename, data, 0644)
	if err != nil {
		return fmt.Errorf("error writing JSON to file: %v", err)
	}

	return nil
}
