//
// libtgvoip is free and unencumbered public domain software.
// For more information, see http://unlicense.org or the UNLICENSE file
// you should have received with this source code distribution.
//

#ifndef LIBTGVOIP_OPUSDECODER_H
#define LIBTGVOIP_OPUSDECODER_H


#include "MediaStreamItf.h"
#include "opus.h"
#include "threading.h"
#include "BlockingQueue.h"
#include "Buffers.h"
#include "EchoCanceller.h"
#include "JitterBuffer.h"
#include <stdio.h>
#include <vector>
#include <memory>

namespace tgvoip{
class OpusDecoder {
public:
	virtual void Start();

	virtual void Stop();

	OpusDecoder(const std::shared_ptr<MediaStreamItf>& dst, bool isAsync, bool needEC);
	OpusDecoder(const std::unique_ptr<MediaStreamItf>& dst, bool isAsync, bool needEC);
	virtual ~OpusDecoder();
	size_t HandleCallback(unsigned char* data, size_t len);
	void SetEchoCanceller(EchoCanceller* canceller);
	void SetFrameDuration(uint32_t duration);
	void SetJitterBuffer(std::shared_ptr<JitterBuffer> jitterBuffer);
	void SetDTX(bool enable);
	void SetLevelMeter(AudioLevelMeter* levelMeter);
	void AddAudioEffect(AudioEffect* effect);
	void RemoveAudioEffect(AudioEffect* effect);

private:
	void Initialize(bool isAsync, bool needEC);
	static size_t Callback(unsigned char* data, size_t len, void* param);
	void RunThread(void* param);
	int DecodeNextFrame();
	::OpusDecoder* dec;
	::OpusDecoder* ecDec;
	BlockingQueue<unsigned char*>* decodedQueue;
	BufferPool* bufferPool;
	unsigned char* buffer;
	unsigned char* lastDecoded;
	unsigned char* processedBuffer;
	size_t outputBufferSize;
	bool running;
    Thread* thread;
	Semaphore* semaphore;
	uint32_t frameDuration;
	EchoCanceller* echoCanceller;
	std::shared_ptr<JitterBuffer> jitterBuffer;
	AudioLevelMeter* levelMeter;
	int consecutiveLostPackets;
	bool enableDTX;
	size_t silentPacketCount;
	std::vector<AudioEffect*> postProcEffects;
	bool async;
	unsigned char nextBuffer[8192];
	unsigned char decodeBuffer[8192];
	bool first;
	size_t nextLen;
	unsigned int packetsPerFrame;
	ptrdiff_t remainingDataLen;
	bool prevWasEC;
	int16_t prevLastSample;
};
}

#endif //LIBTGVOIP_OPUSDECODER_H
