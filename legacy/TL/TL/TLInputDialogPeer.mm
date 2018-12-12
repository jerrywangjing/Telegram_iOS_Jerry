#import "TLInputDialogPeer.h"

#import "../NSInputStream+TL.h"
#import "../NSOutputStream+TL.h"

#import "TLInputPeer.h"

@implementation TLInputDialogPeer


- (int32_t)TLconstructorSignature
{
    TGLog(@"constructorSignature is not implemented for base type");
    return 0;
}

- (int32_t)TLconstructorName
{
    TGLog(@"constructorName is not implemented for base type");
    return 0;
}

- (id<TLObject>)TLbuildFromMetaObject:(std::shared_ptr<TLMetaObject>)__unused metaObject
{
    TGLog(@"TLbuildFromMetaObject is not implemented for base type");
    return nil;
}

- (void)TLfillFieldsWithValues:(std::map<int32_t, TLConstructedValue> *)__unused values
{
    TGLog(@"TLfillFieldsWithValues is not implemented for base type");
}


@end

@implementation TLInputDialogPeer$inputDialogPeerFeed : TLInputDialogPeer


- (int32_t)TLconstructorSignature
{
    return (int32_t)0x2c38b8cf;
}

- (int32_t)TLconstructorName
{
    return (int32_t)0x0321e581;
}

- (id<TLObject>)TLbuildFromMetaObject:(std::shared_ptr<TLMetaObject>)metaObject
{
    TLInputDialogPeer$inputDialogPeerFeed *object = [[TLInputDialogPeer$inputDialogPeerFeed alloc] init];
    object.feed_id = metaObject->getInt32((int32_t)0xf204bed5);
    return object;
}

- (void)TLfillFieldsWithValues:(std::map<int32_t, TLConstructedValue> *)values
{
    {
        TLConstructedValue value;
        value.type = TLConstructedValueTypePrimitiveInt32;
        value.primitive.int32Value = self.feed_id;
        values->insert(std::pair<int32_t, TLConstructedValue>((int32_t)0xf204bed5, value));
    }
}


@end

@implementation TLInputDialogPeer$inputDialogPeer : TLInputDialogPeer


- (int32_t)TLconstructorSignature
{
    return (int32_t)0xfcaafeb7;
}

- (int32_t)TLconstructorName
{
    return (int32_t)0x66e410be;
}

- (id<TLObject>)TLbuildFromMetaObject:(std::shared_ptr<TLMetaObject>)metaObject
{
    TLInputDialogPeer$inputDialogPeer *object = [[TLInputDialogPeer$inputDialogPeer alloc] init];
    object.peer = metaObject->getObject((int32_t)0x9344c37d);
    return object;
}

- (void)TLfillFieldsWithValues:(std::map<int32_t, TLConstructedValue> *)values
{
    {
        TLConstructedValue value;
        value.type = TLConstructedValueTypeObject;
        value.nativeObject = self.peer;
        values->insert(std::pair<int32_t, TLConstructedValue>((int32_t)0x9344c37d, value));
    }
}


@end

