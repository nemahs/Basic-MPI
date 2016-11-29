.386
.model flat,stdcall
option casemap:none

include \masm32\include\windows.inc
include \masm32\include\kernel32.inc
include \masm32\include\wsock32.inc
include \masm32\include\user32.inc
include \masm32\include\shell32.inc
include \masm32\include\masm32.inc
include \masm32\include\msvcrt.inc

includelib \masm32\lib\kernel32.lib
includelib \masm32\lib\wsock32.lib
includelib \masm32\lib\user32.lib
includelib \masm32\lib\shell32.lib
includelib \masm32\lib\masm32.lib

BUFSIZE = 128
maxConnections = 9

.data
;*******************************
;Socket Variables
;*******************************
wsadata WSADATA<>
sock DWORD ?
PORT DWORD 15000
sin sockaddr_in <>
thread DWORD ?
bytesW DWORD ?
sockinfo sockaddr <>
recvbuf BYTE 512 DUP(?)

;*************************************
;Client List
;*************************************
clientList DWORD maxConnections DUP(?)
clientCount BYTE 0

;********************************
;Server Console Variables
;********************************
commandbuf BYTE BUFSIZE DUP(?)
clientswitch BYTE "-c",0
arguments BYTE 128 DUP(?)
outputHandle HANDLE ?
inputHandle HANDLE ?

;********************************************
; Server Commands
;********************************************
killserver	 BYTE "quit",0
sendcommand  BYTE "run",0
listclients  BYTE "list",0
allclients	 BYTE "all",0
closeclient	 BYTE "close",0
help		 BYTE "help",0

;********************************************
; Help Messages
;********************************************
help1		BYTE "run <num> <command> : Runs a command on the specified client. Pass ",34,"all",34," or 0 to send to all clients.",0
help2		BYTE "list : Lists all connected clients.",0
help3		BYTE "close <num> : Closes the connection to the specified client.",0
help4		BYTE "quit : Exits the program.",0
help5		BYTE "help : This message :)",0

;********************************************
; Status Messages
;********************************************
serverstarted		BYTE "Server now running",0
clientstarted		BYTE "Client connected",0
serverline	        BYTE "SERVER>",0
commanderror		BYTE "Unknown command ",0
nothingconnected	BYTE "No clients connected",0
clientclosing		BYTE "Client closing gracefully",0
clientmessage		BYTE "Listening for message...",0

;*************************
;	 	   CODE
;*************************
.code

ExitProcess		PROTO, :DWORD
remoteCommand	PROTO, :DWORD, :DWORD
getInfo			PROTO, :DWORD
startClient		PROTO, :DWORD
cleanupSocket	PROTO, :DWORD

;*************************
;Helper Functions
;*************************
getLength PROC, buffer:DWORD
	push edi
	push esi
	push ecx

	mov edi, buffer
	mov al, 0
	mov ecx, 0
	dec ecx
	cld
	repne scasb
	mov eax, edi
	sub eax, buffer 

	pop ecx
	pop esi
	pop edi
	ret
getLength ENDP

compareString MACRO arg1, arg2, size
	mov esi, arg1
	mov edi, arg2
	mov ecx, size
	repe cmpsb
	cmp ecx,0
ENDM

WriteLine MACRO line
	INVOKE WriteString, line
	INVOKE Crlf
ENDM

WriteString PROC uses eax, string:DWORD
	LOCAL stringlength
	INVOKE getLength, string
	mov stringlength, eax
	INVOKE WriteConsole, outputHandle, string, stringlength, ADDR bytesW, 0
	ret
WriteString ENDP

WriteChar PROC uses eax, char:BYTE
	INVOKE WriteConsole, outputHandle, addr char, 1, addr bytesW, 0
	ret
WriteChar ENDP

Crlf PROC
	.data
		crlf BYTE 13,10	
	.code
		INVOKE WriteConsole, outputHandle, ADDR crlf, LENGTHOF crlf, ADDR bytesW, 0
		ret
Crlf ENDP

ReadString PROC
	add ecx,2
	INVOKE ReadConsole, inputHandle, edx, ecx, addr bytesW, 0
	ret
ReadString ENDP

;*******************
; MAIN
;*******************

main PROC
	;Setup handle
	INVOKE GetStdHandle, STD_OUTPUT_HANDLE
	mov outputHandle, eax
	INVOKE GetStdHandle, STD_INPUT_HANDLE
	mov inputHandle, eax

	INVOKE GetCommandLine
	mov edi, eax
	inc edi
	INVOKE getLength, edi
	mov ecx,eax
	mov al, '"'
	repne scasb
	.if ecx == 0
		INVOKE GetCommandLine
		mov edi,eax
		INVOKE getLength, edi
		mov ecx,eax
		mov al, ' '
		repne scasb
	.endif

	inc edi
	cld
	mov esi,edi
	mov edi, OFFSET arguments
	INVOKE getLength, esi
	mov ecx,eax
	rep movsb
	call checkFlag
	INVOKE ExitProcess, 0
main ENDP

checkFlag PROC
	compareString OFFSET arguments, OFFSET clientswitch, LENGTHOF clientswitch
	.if ZERO?
		jmp client
	.else
		jmp server
	.endif
checkFlag ENDP

startServer PROC
	invoke WSAStartup, 101h, addr wsadata
	invoke socket,AF_INET,SOCK_STREAM,0
	mov sock,eax
	mov sin.sin_family, AF_INET
	invoke htons, PORT
	mov sin.sin_port, ax
	invoke bind, sock, ADDR sin, SIZEOF sin
	;Start listening on another thread
	mov eax, OFFSET serverLoop
	INVOKE CreateThread,NULL,NULL, eax, NULL,0, ADDR thread
	ret
startServer ENDP

serverLoop PROC
	INVOKE listen, sock, maxConnections
	serverLoopTop:
		INVOKE accept,sock,NULL,NULL
		movzx ebx, clientCount
		mov clientList[ebx * SIZEOF DWORD], eax
		inc clientCount
	jmp serverLoopTop
serverLoop ENDP

server PROC
	;Start the socket connections
	call startServer
	WriteLine OFFSET serverstarted

	;Loop accepting commands and doing things
	mainloop:
		INVOKE WriteString, OFFSET serverline
		mov edx, OFFSET commandbuf
		mov ecx, SIZEOF commandbuf
		call ReadString

		;Parse string
		;case "quit"
		compareString OFFSET commandbuf, OFFSET killserver, LENGTHOF killserver
		jnz	@f
			call stopServer
			ret
		@@:
		;case "list"
		compareString OFFSET commandbuf, OFFSET listclients, LENGTHOF listclients
		jnz @f
			call servList
			jmp mainloop
		@@:
		;case "close"
		compareString OFFSET commandbuf, OFFSET closeclient, LENGTHOF closeclient
		jnz @f
			mov edi, OFFSET commandbuf
			mov al, ' '
			inc edi
			cld
			mov ecx, 5
			repne scasb
			mov eax,[edi]
			and eax, 111b
			dec eax
			INVOKE cleanupSocket, eax
			jmp mainloop
		@@:
		;case "help"
		compareString OFFSET commandbuf, OFFSET help, LENGTHOF help
		jnz @f
			WriteLine OFFSET help1
			WriteLine OFFSET help2
			WriteLine OFFSET help3
			WriteLine OFFSET help4
			WriteLine OFFSET help5
			jmp mainloop
		@@:
		;case "run"
		compareString OFFSET sendcommand, OFFSET commandbuf, LENGTHOF sendcommand
		jnz nothing
			mov ebx, edi
			mov al, ' '
			inc edi
			cld
			mov ecx, 3
			repne scasb
			INVOKE remoteCommand, edi, ebx
			jmp mainloop
		nothing: 
			INVOKE WriteString, OFFSET commanderror
			mov edx,edi
			sub edx, 1
			WriteLine edx
			jmp mainloop
	ret
server ENDP

servList PROC
	movzx eax, clientCount
	;Nothing
	.if eax == 0
		INVOKE WriteString, OFFSET nothingconnected
		call Crlf
		ret
	.else
		mov ecx,0
		.while cl < clientCount
			inc cl
			push ecx
			or ecx, 30h
			INVOKE WriteChar, cl
			INVOKE WriteChar, ':'
			INVOKE WriteChar, ' '
			INVOKE getInfo, ecx
			WriteLine eax
			pop ecx
		.endw
	.endif
	ret
servList ENDP

getInfo PROC, num:DWORD
	LOCAL len: DWORD
	mov len, SIZEOF sockinfo
	mov ecx, num
	dec ecx
	INVOKE inet_ntoa, ADDR (sockaddr_in PTR clientList[ecx]).sin_addr
	ret
getInfo ENDP

sendData PROC, num:DWORD, message:DWORD
	LOCAL iResult:DWORD
	.if num == 0
		movzx ecx, clientCount
		mov edx, 0

		.if ecx == 0
			ret
		.endif
		looptop:
			push ecx
			push edx
			INVOKE getLength, message
			mov ebx,eax
			pop edx
			mov esi, clientList[edx * SIZEOF DWORD]
			push edx
			INVOKE send, esi, message, ebx, 0
			mov iResult, eax

			.if iResult == 0
				INVOKE cleanupSocket, edx
			.endif
			pop edx
			pop ecx
			inc edx
		LOOP looptop
	.else
		INVOKE getLength, message
		mov ebx,eax
		mov ecx, num
		dec ecx
		mov esi, clientList[ecx * SIZEOF DWORD]
		INVOKE send, esi, message, ebx, 0
		mov iResult, eax
		.if iResult == 0
			mov edx, num
			dec edx
			INVOKE cleanupSocket, edx
		.endif
	.endif
	ret
sendData ENDP

cleanupSocket PROC, num: DWORD
	mov ecx, num
	push ecx
	INVOKE closesocket, clientList[ecx * SIZEOF DWORD]
	pop ecx
	movzx edx, clientCount
	.while ecx < edx
		mov eax, clientList[ecx * SIZEOF DWORD + SIZEOF DWORD]
		mov clientList[ecx * SIZEOF DWORD], eax
		inc ecx
	.endw
	dec clientCount
	ret
cleanupSocket ENDP

stopServer PROC
	INVOKE TerminateThread, thread, 0

	;Close client sockets
	mov ecx, 0
	.while cl < clientCount
		push ecx
		INVOKE closesocket, clientList[ecx * SIZEOF DWORD]
		pop ecx
		inc cl
	.endw
	INVOKE closesocket, sock
	INVOKE WSACleanup
	ret
stopServer ENDP

remoteCommand PROC , message: DWORD, target: DWORD
	;Parse target
		compareString target, OFFSET allclients, LENGTHOF allclients
		jz sendtoall
		;See if this is a number
		mov eax, target
		mov eax ,[eax]
		and eax, 111b
		.if eax < maxConnections
			INVOKE sendData, eax, message
			ret
		.endif
		sendtoall:
			INVOKE sendData, 0, message
			ret
remoteCommand ENDP

;*************************
;		CLIENT CODE
;*************************

client PROC
	;CLIENT
	mov al, ' '
	mov ecx, 3
	repne scasb
	INVOKE startClient, edi
	ret
client ENDP

startClient PROC, address:DWORD

	INVOKE WSAStartup, 101h, addr wsadata
	INVOKE socket, AF_INET,SOCK_STREAM,0
	mov sock,eax
	mov sin.sin_family, AF_INET
	INVOKE htons, PORT
	mov sin.sin_port, ax
	INVOKE inet_addr, address
	mov sin.sin_addr, eax

	INVOKE connect,sock,addr sin, SIZEOF sin
	.if eax == 0
		clientLoop:
			INVOKE WriteString, OFFSET clientmessage
			INVOKE recv,sock, addr recvbuf,512,0

			.if eax > 0 && !SIGN?
				WriteLine addr recvbuf
				INVOKE _imp__system, addr recvbuf
			.elseif eax == 0
				Call Crlf
				WriteLine OFFSET clientclosing
				jmp clientEnd
			.else
				jmp clientEnd
			.endif
		jmp clientLoop
	.else
		;ERROR
		INVOKE WSAGetLastError
	.endif
	clientEnd:
	INVOKE closesocket,sock
	INVOKE WSACleanup
	ret
startClient ENDP

END main