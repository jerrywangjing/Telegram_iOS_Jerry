//
// libtgvoip is free and unencumbered public domain software.
// For more information, see http://unlicense.org or the UNLICENSE file
// you should have received with this source code distribution.
//

#ifndef LIBTGVOIP_OPUSENCODER_H
#define LIBTGVOIP_OPUSENCODER_H


#include "MediaStreamItf.h"
#include "opus.h"
#include "threading.h"
#include "BlockingQueue.h"
#include "Buffers.h"
#include "EchoCanceller.h"

#include <stdint.h>

namespace tgvoip{
class OpusEncoder{
public:
	OpusEncoder(MediaStreamItf* source, bool needSecondary);
	virtual ~OpusEncoder();
	virtual void Start();
	virtual void Stop();
	void SetBitrate(uint32_t bitrate);
	void SetEchoCanceller(EchoCanceller* aec);
	void SetOutputFrameDuration(uint32_t duration);
	void SetPacketLoss(int percent);
	int GetPacketLoss();
	uint32_t GetBitrate();
	void SetDTX(bool enable);
	void SetLevelMeter(AudioLevelMeter* levelMeter);
	void SetCallback(void (*f)(unsigned char*, size_t, unsigned char*, size_t, void*), void* param);
	void SetSecondaryEncoderEnabled(bool enabled);

private:
	static size_t Callback(unsigned char* data, size_t len, void* param);
	void RunThread(void* arg);
	void Encode(unsigned char* data, size_t len);
	void InvokeCallback(unsigned char* data, size_t length, unsigned char* secondaryData, size_t secondaryLength);
	MediaStreamItf* source;
	::OpusEncoder* enc;
	::OpusEncoder* secondaryEncoder;
	unsigned char buffer[4096];
	uint32_t requestedBitrate;
	uint32_t currentBitrate;
	Thread* thread;
	BlockingQueue<unsigned char*> queue;
	BufferPool bufferPool;
	EchoCanceller* echoCanceller;
	int complexity;
	bool running;
	uint32_t frameDuration;
	int packetLossPercent;
	uint32_t mediumCorrectionBitrate;
	uint32_t strongCorrectionBitrate;
	double mediumCorrectionMultiplier;
	double strongCorrectionMultiplier;
	AudioLevelMeter* levelMeter;
	bool secondaryEncoderEnabled;

	void (*callback)(unsigned char*, size_t, unsigned char*, size_t, void*);
	void* callbackParam;
};
}

#endif //LIBTGVOIP_OPUSENCODER_H
